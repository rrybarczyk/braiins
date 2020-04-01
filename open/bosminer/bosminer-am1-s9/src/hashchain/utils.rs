// Copyright (C) 2020  Braiins Systems s.r.o.
//
// This file is part of Braiins Open-Source Initiative (BOSI).
//
// BOSI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Common Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Common Public License for more details.
//
// You should have received a copy of the GNU Common Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
// Please, keep in mind that we may also license BOSI or any part thereof
// under a proprietary license. For more information on the terms and conditions
// of such proprietary license or if you have any other questions, please
// contact us at opensource@braiins.com.

//! Utilities to calculate baudrates

use crate::error::{self, ErrorKind};

/// Helper method that calculates baud rate clock divisor value for the specified baud rate.
///
/// The calculation follows the same scheme for the hashing chips as well as for the FPGA IP core
///
/// * `baud_rate` - requested baud rate
/// * `base_clock_hz` - base clock for the UART peripheral
/// * `base_clock_div` - divisor for the base clock
/// Return a baudrate divisor and actual baud rate or an error
pub fn calc_baud_clock_div(
    baud_rate: usize,
    base_clock_hz: usize,
    base_clock_div: usize,
) -> error::Result<(usize, usize)> {
    const MAX_BAUD_RATE_ERR_PERC: usize = 5;
    // The actual calculation is:
    // base_clock_hz / (base_clock_div * baud_rate) - 1
    // We have to mathematically round the calculated divisor in fixed point arithmethic
    let baud_div = (10 * base_clock_hz / (base_clock_div * baud_rate) + 5) / 10 - 1;
    let actual_baud_rate = base_clock_hz / (base_clock_div * (baud_div + 1));

    //
    let baud_rate_diff = if actual_baud_rate > baud_rate {
        actual_baud_rate - baud_rate
    } else {
        baud_rate - actual_baud_rate
    };
    // the baud rate has to be within a few percents
    if baud_rate_diff > (MAX_BAUD_RATE_ERR_PERC * baud_rate / 100) {
        Err(ErrorKind::BaudRate(format!(
            "requested {} baud, resulting {} baud",
            baud_rate, actual_baud_rate
        )))?
    }
    Ok((baud_div, actual_baud_rate))
}

/// Helper method to calculate time to finish one piece of work
///
/// * `n_midstates` - number of midstates
/// * `pll_frequency` - frequency of chip in Hz
/// Return a number of seconds.
///
/// The formula for work_delay is:
///
///   work_delay = space_size_of_one_work / computation_speed; [sec, hashes, hashes_per_sec]
///
/// In our case it would be
///
///   work_delay = n_midstates * 2^32 / (freq * num_chips * cores_per_chip)
///
/// Unfortunately the space is not divided evenly, some nonces get never computed.
/// The current conjecture is that nonce space is divided by chip/core address,
/// ie. chip number 0x1a iterates all nonces 0x1axxxxxx. That's 6 bits of chip_address
/// and 7 bits of core_address. Putting it all together:
///
///   work_delay = n_midstates * num_chips * cores_per_chip * 2^(32 - 7 - 6) / (freq * num_chips * cores_per_chip)
///
/// Simplify:
///
///   work_delay = n_midstates * 2^19 / freq
///
/// Last but not least, we apply fudge factor of 0.9 and send work 11% faster to offset
/// delays when sending out/generating work/chips not getting proper work...:
///
///   work_delay = 0.9 * n_midstates * 2^19 / freq
pub fn calculate_work_delay_for_pll(n_midstates: usize, pll_frequency: usize) -> f64 {
    let space_size_per_core: u64 = 1 << 19;
    0.9 * (n_midstates as u64 * space_size_per_core) as f64 / pll_frequency as f64
}

/// Helper method to convert seconds to FPGA ticks suitable to be written
/// to `WORK_TIME` FPGA register.
///
/// Returns number of ticks.
pub fn secs_to_fpga_ticks(fpga_freq: usize, secs: f64) -> u32 {
    (secs * fpga_freq as f64) as u32
}

#[cfg(test)]
mod test {
    use super::*;

    use crate::bm1387;
    use crate::hashchain;
    use crate::io;

    #[test]
    fn test_calc_baud_div_correct_baud_rate_bm1387() {
        // these are sample baud rates for communicating with BM1387 chips
        let correct_bauds_and_divs = [
            (115_200usize, 26usize),
            (460_800, 6),
            (1_500_000, 1),
            (3_000_000, 0),
        ];
        for (baud_rate, baud_div) in correct_bauds_and_divs.iter() {
            let (baud_clock_div, actual_baud_rate) = calc_baud_clock_div(
                *baud_rate,
                hashchain::CHIP_OSC_CLK_HZ,
                bm1387::CHIP_OSC_CLK_BASE_BAUD_DIV,
            )
            .unwrap();
            assert_eq!(
                baud_clock_div, *baud_div,
                "Calculated baud divisor doesn't match, requested: {} baud, actual: {} baud",
                baud_rate, actual_baud_rate
            )
        }
    }

    #[test]
    fn test_calc_baud_div_correct_baud_rate_fpga() {
        // these are baudrates commonly used with UART on FPGA
        let correct_bauds_and_divs = [(115_740usize, 53usize), (1_562_500, 3), (3_125_000, 1)];
        for &(baud_rate, baud_div) in correct_bauds_and_divs.iter() {
            let (baud_clock_div, _actual_baud_rate) =
                calc_baud_clock_div(baud_rate, io::F_CLK_SPEED_HZ, io::F_CLK_BASE_BAUD_DIV)
                    .expect("failed to calculate divisor");
            assert_eq!(baud_clock_div, baud_div);
        }
    }

    /// Test higher baud rate than supported
    #[test]
    fn test_calc_baud_div_over_baud_rate_bm1387() {
        let result = calc_baud_clock_div(
            3_500_000,
            hashchain::CHIP_OSC_CLK_HZ,
            bm1387::CHIP_OSC_CLK_BASE_BAUD_DIV,
        );
        assert!(
            result.is_err(),
            "Baud clock divisor unexpectedly calculated!"
        );
    }

    /// Test work_time computation
    #[test]
    fn test_work_time_computation() {
        // you need to recalc this if you change asic diff or fpga freq
        assert_eq!(
            secs_to_fpga_ticks(
                io::F_CLK_SPEED_HZ,
                calculate_work_delay_for_pll(1, 650_000_000)
            ),
            36296
        );
    }
}
