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

//! S9 sensor structure implementation

use ii_hwmon::{self, Value};

use crate::monitor;
use crate::sensor::SensorResult;

use std::fmt;

/// Helper structure for sending temperatures to Monitor
#[derive(Debug, Clone)]
pub struct Hashboard(pub(crate) SensorResult);

impl Hashboard {
    fn measurement(&self) -> Option<&ii_hwmon::Reading> {
        match self.0 {
            SensorResult::Valid(ref m) => Some(m),
            _ => None,
        }
    }

    /// These methods will probably go away once I decide what's the best interface for accessing
    /// temperature information from the likes of cgminer API and tuner
    pub fn local(&self) -> Option<f32> {
        self.measurement()
            .and_then(|m| Option::from(m.local.clone()))
    }

    pub fn remote(&self) -> Option<f32> {
        self.measurement()
            .and_then(|m| Option::from(m.remote.clone()))
    }
}

impl fmt::Display for Hashboard {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.0 {
            SensorResult::Valid(ref temp) => {
                write!(f, "{},{}", temp.local.to_string(), temp.remote.to_string())
            }
            other => fmt::Debug::fmt(other, f),
        }
    }
}

impl monitor::SummaryTemperature for Hashboard {
    fn summary_temperature(&self) -> monitor::Temperature {
        match &self.0 {
            SensorResult::Valid(ref temp) => match temp.remote {
                // remote is chip temperature
                Value::Ok(t_remote) => match temp.local {
                    Value::Ok(t_local) => monitor::Temperature::Ok(t_remote.max(t_local)),
                    _ => monitor::Temperature::Ok(t_remote),
                },
                _ => {
                    // fake chip temperature from local (PCB) temperature
                    match temp.local {
                        Value::Ok(t_local) => monitor::Temperature::Ok(t_local + 15.0),
                        _ => monitor::Temperature::Unknown,
                    }
                }
            },
            _ => monitor::Temperature::Unknown,
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use approx::assert_relative_eq;
    use monitor::SummaryTemperature;

    /// Test that faking S9 chip temperature from board temperature works
    #[test]
    fn test_summary_temperature() {
        let sensor_result = Hashboard(SensorResult::Valid(ii_hwmon::Reading {
            local: Value::Ok(10.0),
            remote: Value::Ok(22.0),
        }));
        match sensor_result.summary_temperature() {
            monitor::Temperature::Ok(t) => assert_relative_eq!(t, 22.0),
            _ => panic!("missing temperature"),
        };
        let sensor_result = Hashboard(SensorResult::Valid(ii_hwmon::Reading {
            local: Value::Ok(10.0),
            remote: Value::OpenCircuit,
        }));
        match sensor_result.summary_temperature() {
            monitor::Temperature::Ok(t) => assert_relative_eq!(t, 25.0),
            _ => panic!("missing temperature"),
        };
        let sensor_result = Hashboard(SensorResult::Valid(ii_hwmon::Reading {
            local: Value::InvalidReading,
            remote: Value::OpenCircuit,
        }));
        assert_eq!(
            sensor_result.summary_temperature(),
            monitor::Temperature::Unknown
        );
    }
}
