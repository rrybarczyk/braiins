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

//! Glitch counter manipulation

use super::counters;
use crate::error;
use crate::io;

/// Intepretation of `GlitchData` for S9
pub struct RawGlitchesS9 {
    pub i2c_scl: usize,
    pub i2c_sda: usize,
    pub j6_rx: usize,
    pub j7_rx: usize,
    pub j8_rx: usize,
}

impl From<io::GlitchData> for RawGlitchesS9 {
    fn from(data: io::GlitchData) -> Self {
        Self {
            i2c_scl: data.chan[0] as usize,
            i2c_sda: data.chan[1] as usize,
            j6_rx: data.chan[2] as usize,
            j7_rx: data.chan[3] as usize,
            j8_rx: data.chan[4] as usize,
        }
    }
}

impl RawGlitchesS9 {
    pub fn get_glitches_for_hashboard(&self, hashboard_idx: usize) -> counters::Glitches {
        counters::Glitches {
            i2c_scl: self.i2c_scl,
            i2c_sda: self.i2c_sda,
            uart_rx: match hashboard_idx {
                6 => self.j6_rx,
                7 => self.j7_rx,
                8 => self.j8_rx,
                _ => panic!("BUG: unsupported hashboard index"),
            },
        }
    }
}

/// Object to keep tabs on current state of `GlitchData` in hardware and to compute difference to
/// figure out number of new glitches.
pub struct Monitor {
    hw: io::GlitchMonitor,
    last_state: io::GlitchData,
}

impl Monitor {
    pub fn open() -> error::Result<Self> {
        let hw = io::GlitchMonitor::new()?;
        let last_state = hw.read();

        Ok(Self { hw, last_state })
    }

    /// Compute difference from last state
    fn glitch_diff(a: &io::GlitchData, b: &io::GlitchData) -> io::GlitchData {
        let mut out: io::GlitchData = Default::default();
        for i in 0..out.chan.len() {
            out.chan[i] = b.chan[i].wrapping_sub(a.chan[i]);
        }
        out
    }

    pub fn fetch_new(&mut self) -> RawGlitchesS9 {
        let cur_state = self.hw.read();
        let diff = Self::glitch_diff(&self.last_state, &cur_state);
        self.last_state = cur_state;
        diff.into()
    }
}
