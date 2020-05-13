// Copyright (C) 2020  Braiins Systems s.r.o.
//
// This file is part of Braiins Open-Source Initiative (BOSI).
//
// BOSI is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
// Please, keep in mind that we may also license BOSI or any part thereof
// under a proprietary license. For more information on the terms and conditions
// of such proprietary license or if you have any other questions, please
// contact us at opensource@braiins.com.

//! Temperature sensor reading and error correction strategy

use ii_hwmon::{self, Value};

use ii_logging::macros::*;

use tokio::time::delay_for;

use std::time::Duration;

use crate::error;

use crate::utils;

#[derive(Debug, Clone)]
pub enum SensorResult {
    NotInitialized,
    ReadFailed,
    Valid(ii_hwmon::Reading),
    Broken,
    NotPresent,
}

pub struct Sensor {
    hw: Box<dyn ii_hwmon::TempSensor>,
    name: String,
    is_broken: bool,
    error_average: f32,
    last_max_temp: Option<f32>,
}

impl Sensor {
    /// Number of attempts to try read temperature again if it doesn't look right
    const MAX_TEMP_REREAD_ATTEMPTS: usize = 3;

    /// Temperature difference that is considerd to be a "sudden temperature change"
    const MAX_SUDDEN_TEMPERATURE_JUMP: f32 = 12.0;

    /// Maximum number of errors before temperature sensor is disabled
    const MAX_SENSOR_ERRORS: usize = 10;

    /// Delay before repeating the read operation in case of sensor reading error
    const REPEATED_READ_DELAY: Duration = Duration::from_millis(200);

    pub fn new(name: String, hw: Box<dyn ii_hwmon::TempSensor>) -> Self {
        Self {
            hw,
            name,
            is_broken: false,
            error_average: 0.0,
            last_max_temp: None,
        }
    }

    fn add_error(&mut self) {
        self.error_average += 1.0;

        // If there's too many errors, just disable this sensor
        if self.error_average >= Self::MAX_SENSOR_ERRORS as f32 {
            error!(
                "Sensor {}: Too many sensor errors, disabling sensor",
                self.name
            );
            self.is_broken = true;
        }
    }

    fn decay_error(&mut self) {
        // Decay 30% of errors an hour: update it every 5 seconds, so one hour is
        // `error_counter * 0.9995^(3600/5) = error_counter * 0.70`
        self.error_average *= 0.9995;
    }

    /// Read temperature and implement special error handling that aggregates errors from the
    /// sensors. The point is to mark sensor as broken if it doesn't work properly in a long run
    /// see `add_error` + `decay_error`.
    pub async fn read(&mut self) -> SensorResult {
        if self.is_broken {
            return SensorResult::Broken;
        }
        self.decay_error();

        let mut attempts_left = Self::MAX_TEMP_REREAD_ATTEMPTS;
        loop {
            // Read temperature sensor
            match self.hw.read().await.map_err(|e| error::Error::from(e)) {
                Ok(temp) => {
                    info!("Sensor {}: {:?}", self.name, temp);

                    let (local_error, local_temp) = match temp.local {
                        Value::Ok(t) => (false, Some(t)),
                        _ => (true, None),
                    };
                    let (remote_error, remote_temp) = match temp.remote {
                        Value::NotPresent => (false, None),
                        Value::Ok(t) => (false, Some(t)),
                        _ => (true, None),
                    };

                    let max_temp = utils::aggregate(f32::max, local_temp, remote_temp);
                    if attempts_left > 0 {
                        if let Some(last_max_t) = self.last_max_temp {
                            if let Some(max_t) = max_temp {
                                if (max_t - last_max_t).abs() >= Self::MAX_SUDDEN_TEMPERATURE_JUMP {
                                    warn!("Sensor {}: temperature suddenly jumped from {} to {}, retrying", self.name, last_max_t, max_t);

                                    self.add_error();
                                    // Exit early if we broke the sensor already
                                    if self.is_broken {
                                        return SensorResult::Broken;
                                    }

                                    // Do not send anything out yet, just wait a bit and then try to read
                                    // the temperature again
                                    delay_for(Self::REPEATED_READ_DELAY).await;
                                    attempts_left -= 1;
                                    continue;
                                }
                            }
                        }
                    }

                    if max_temp.is_some() {
                        self.last_max_temp = max_temp;
                    }

                    if local_error || remote_error {
                        self.add_error();
                    }

                    return SensorResult::Valid(temp);
                }
                Err(e) => {
                    error!("Sensor {}: read failed: {}", self.name, e);
                    self.add_error();
                    return SensorResult::ReadFailed;
                }
            }
        }
    }
}
