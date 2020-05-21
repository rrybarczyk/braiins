----------------------------------------------------------------------------------------------------
-- Copyright (C) 2020  Braiins Systems s.r.o.
--
-- This file is part of Braiins Open-Source Initiative (BOSI).
--
-- BOSI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- Please, keep in mind that we may also license BOSI or any part thereof
-- under a proprietary license. For more information on the terms and conditions
-- of such proprietary license or if you have any other questions, please
-- contact us at opensource@braiins.com.
----------------------------------------------------------------------------------------------------
-- Project Name:   Braiins OS
-- Description:    Board Controller
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (05.05.2020)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity board_ctrl_core is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- Control & status signals
        control         : in  std_logic_vector(5 downto 0);
        status          : out std_logic_vector(0 downto 0);

        -- FPGA IOs
        pin_L14         : in    std_logic;    -- J4.Rx (in) or FAN3.SENSE (in, C49)
        pin_M14         : inout std_logic;    -- J4.Tx (out) or FAN4.SENSE (in, C49)
        pin_E11         : out   std_logic;    -- FAN[1,2].PWM (out)
        pin_E12         : inout std_logic;    -- FAN[3,4].PWM (out) or NC
        pin_F13         : in    std_logic;    -- FAN3.SENSE (in, C52) or NC
        pin_F14         : in    std_logic;    -- FAN4.SENSE (in, C52) or NC

        -- UART J4 interface
        uart_rxd        : in  std_logic;
        uart_txd        : out std_logic;

        -- Fan Controller
        fan_pwm         : in  std_logic_vector(1 downto 0);
        fan_sense       : out std_logic_vector(1 downto 0)
    );
end board_ctrl_core;

architecture rtl of board_ctrl_core is

    ------------------------------------------------------------------------------------------------
    -- synchronization input signals into clock domain
    signal pin_L14_q : std_logic_vector(2 downto 0);
    signal pin_M14_q : std_logic_vector(2 downto 0);
    signal pin_F13_q : std_logic_vector(2 downto 0);
    signal pin_F14_q : std_logic_vector(2 downto 0);

    -- synchronization output signals into clock domain
    signal uart_rxd_q : std_logic;

    ------------------------------------------------------------------------------------------------
    -- select signals for individual boards
    signal select_C43 : std_logic;
    signal select_C44 : std_logic;
    signal select_C47 : std_logic;
    signal select_C49 : std_logic;
    signal select_C52 : std_logic;

    -- UART select signal for multiple boards
    signal uart_sel   : std_logic;

    ------------------------------------------------------------------------------------------------
    -- IO buffer M14 signals
    signal pin_M14_i : std_logic;
    signal pin_M14_o : std_logic;
    signal pin_M14_t : std_logic;

    -- IO buffer E12 signals
    signal pin_E12_i : std_logic;
    signal pin_E12_o : std_logic;
    signal pin_E12_t : std_logic;

begin

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    p_input_sync: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                pin_L14_q <= (others => '1');
                pin_M14_q <= (others => '1');
                pin_F13_q <= (others => '1');
                pin_F14_q <= (others => '1');
            else
                pin_L14_q <= pin_L14 & pin_L14_q(2 downto 1);
                pin_M14_q <= pin_M14_i & pin_M14_q(2 downto 1);
                pin_F13_q <= pin_F13 & pin_F13_q(2 downto 1);
                pin_F14_q <= pin_F14 & pin_F14_q(2 downto 1);
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- synchronization output signal into clock domain
    p_output_sync: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                uart_rxd_q <= '1';
            else
                uart_rxd_q <= uart_rxd;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- select signals for individual boards
    select_C43 <= '1' when (control(5 downto 0) = "101011") else '0';
    select_C44 <= '1' when (control(5 downto 0) = "101100") else '0';
    select_C47 <= '1' when (control(5 downto 0) = "101111") else '0';
    select_C49 <= '1' when (control(5 downto 0) = "110001") else '0';
    select_C52 <= '1' when (control(5 downto 0) = "110100") else '0';

    -- UART select signal for multiple boards
    uart_sel <= select_C43 or select_C44 or select_C52;

    ------------------------------------------------------------------------------------------------
    -- set error in none board select signal is set
    status(0) <= select_C43 or select_C44 or select_C47 or select_C49 or select_C52;

    ------------------------------------------------------------------------------------------------
    -- Fan multiplexer
    fan_sense <=
        pin_M14_q(0) & pin_L14_q(0) when (select_C49 = '1') else
        pin_F14_q(0) & pin_F13_q(0) when (select_C52 = '1') else
        "00";

    -- UART Multiplexer
    uart_txd <= pin_L14_q(0) when (uart_sel = '1') else '1';

    -- FPGA IO drivers
    pin_E11 <= fan_pwm(0);

    pin_M14_o <= uart_rxd_q;
    pin_M14_t <= not uart_sel;

    -- dummy use of pin_E12_i to avoid DRC warning [DRC BUFC-1]
    pin_E12_o <= fan_pwm(1) when (select_C52 = '1') else pin_E12_i;
    pin_E12_t <= not select_C52;

    ------------------------------------------------------------------------------------------------
    -- Single-ended Bi-directional Buffers
    i_iobuf_M14 : IOBUF
        generic map (
            DRIVE => 16,
            IOSTANDARD => "DEFAULT",
            SLEW => "SLOW"
        )
        port map (
            O  => pin_M14_i,   -- Buffer output
            IO => pin_M14,     -- Buffer inout port (connect directly to top-level port)
            I  => pin_M14_o,   -- Buffer input
            T  => pin_M14_t    -- 3-state enable input, high=input, low=output
        );

    i_iobuf_E12 : IOBUF
        generic map (
            DRIVE => 16,
            IOSTANDARD => "DEFAULT",
            SLEW => "SLOW"
        )
        port map (
            O  => pin_E12_i,   -- Buffer output
            IO => pin_E12,     -- Buffer inout port (connect directly to top-level port)
            I  => pin_E12_o,   -- Buffer input
            T  => pin_E12_t    -- 3-state enable input, high=input, low=output
        );

end rtl;
