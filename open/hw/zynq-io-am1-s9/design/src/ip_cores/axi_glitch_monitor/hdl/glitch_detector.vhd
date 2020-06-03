----------------------------------------------------------------------------------------------------
-- Copyright (C) 2019  Braiins Systems s.r.o.
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
-- Description:    Glitch Detector
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (19.05.2020)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity glitch_detector is
    generic (
        C_MAX_WIDTH  : integer range 1 to 7     -- max. width of glitch to detect in clk periods
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- Control signals
        enable       : in  std_logic;
        clear        : in  std_logic;

        -- Input signal
        sig_in       : in  std_logic;

        -- Output data
        glitch_cnt   : out std_logic_vector(31 downto 0);
        glitch_width : out std_logic_vector(2 downto 0)
    );
end glitch_detector;

architecture rtl of glitch_detector is

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    signal input_q       : std_logic_vector(3 downto 0);

    -- edge and glitch detection signals
    signal edge          : std_logic;
    signal glitch        : std_logic;

    ------------------------------------------------------------------------------------------------
    -- pulse width counter
    signal cnt_d          : unsigned(2 downto 0);
    signal cnt_q          : unsigned(2 downto 0);

    -- output registers
    signal glitch_cnt_d   : unsigned(31 downto 0);
    signal glitch_cnt_q   : unsigned(31 downto 0);

    signal glitch_width_d : unsigned(2 downto 0);
    signal glitch_width_q : unsigned(2 downto 0);

begin

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    p_input_sync: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                input_q <= (others => '0');
            else
                input_q <= sig_in & input_q(3 downto 1);
            end if;
        end if;
    end process;

    -- detect edge
    edge <= input_q(1) xor input_q(0);

    ------------------------------------------------------------------------------------------------
    -- sequential part of pulse width counter
    p_cnt_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                cnt_q <= (others => '0');
            else
                cnt_q <= cnt_d;
            end if;
        end if;
    end process;

    -- combinational part of pulse width counter
    p_cnt_cmb: process (edge, cnt_q, enable) begin
        -- default assignment to registers and signals
        cnt_d <= cnt_q;
        glitch <= '0';

        if (cnt_q /= 0) or ((cnt_q = 0) and (edge = '1')) then
            cnt_d <= cnt_q + 1;
        end if;

        if (cnt_q = C_MAX_WIDTH) then
            cnt_d <= (others => '0');
        end if;

        if ((cnt_q /= 0) and (edge = '1') and (enable = '1')) then
            cnt_d <= (others => '0');
            glitch <= '1';
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- sequential part of latch registers
    p_latch_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                glitch_cnt_q <= (others => '0');
                glitch_width_q <= (others => '0');
            else
                glitch_cnt_q <= glitch_cnt_d;
                glitch_width_q <= glitch_width_d;
            end if;
        end if;
    end process;

    -- combinational part of latch registers
    p_latch_cmb: process (glitch, clear, cnt_q, glitch_cnt_q, glitch_width_q) begin
        -- default assignment to registers and signals
        glitch_cnt_d <= glitch_cnt_q;
        glitch_width_d <= glitch_width_q;

        if (glitch = '1') then
            glitch_cnt_d <= glitch_cnt_q + 1;
            glitch_width_d <= cnt_q;
        end if;

        if (clear = '1') then
            glitch_cnt_d <= (others => '0');
            glitch_width_d <= (others => '0');
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- output signals
    glitch_cnt <= std_logic_vector(glitch_cnt_q);
    glitch_width <= std_logic_vector(glitch_width_q);

end rtl;
