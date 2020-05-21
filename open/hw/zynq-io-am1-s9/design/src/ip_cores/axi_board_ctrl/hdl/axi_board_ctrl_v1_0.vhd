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
-- Description:    Top module of Board Controller IP core
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (05.05.2020)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_board_ctrl_v1_0 is
    generic (
        -- Users to add parameters here

        C_DEFAULT_BOARD    : integer    := 0;

        -- User parameters ends
        -- Do not modify the parameters beyond this line


        -- Parameters of Axi Slave Bus Interface S_AXI
        C_S_AXI_DATA_WIDTH : integer    := 32;
        C_S_AXI_ADDR_WIDTH : integer    := 5
    );
    port (
        -- Users to add ports here

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
        fan_sense       : out std_logic_vector(1 downto 0);

        -- User ports ends
        -- Do not modify the ports beyond this line


        -- Ports of Axi Slave Bus Interface S_AXI
        s_axi_aclk      : in std_logic;
        s_axi_aresetn   : in std_logic;
        s_axi_awaddr    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot    : in std_logic_vector(2 downto 0);
        s_axi_awvalid   : in std_logic;
        s_axi_awready   : out std_logic;
        s_axi_wdata     : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb     : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid    : in std_logic;
        s_axi_wready    : out std_logic;
        s_axi_bresp     : out std_logic_vector(1 downto 0);
        s_axi_bvalid    : out std_logic;
        s_axi_bready    : in std_logic;
        s_axi_araddr    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot    : in std_logic_vector(2 downto 0);
        s_axi_arvalid   : in std_logic;
        s_axi_arready   : out std_logic;
        s_axi_rdata     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp     : out std_logic_vector(1 downto 0);
        s_axi_rvalid    : out std_logic;
        s_axi_rready    : in std_logic
    );
end axi_board_ctrl_v1_0;

architecture rtl of axi_board_ctrl_v1_0 is

begin

    -- Instantiation of Axi Bus Interface S_AXI
    i_board_ctrl_S_AXI : entity work.board_ctrl_S_AXI
        generic map (
            C_DEFAULT_BOARD    => C_DEFAULT_BOARD,
            C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
        )
        port map (
            -- FPGA IOs
            pin_L14         => pin_L14,
            pin_M14         => pin_M14,
            pin_E11         => pin_E11,
            pin_E12         => pin_E12,
            pin_F13         => pin_F13,
            pin_F14         => pin_F14,

            -- UART J4 interface
            uart_rxd        => uart_rxd,
            uart_txd        => uart_txd,

            -- Fan Controller
            fan_pwm         => fan_pwm,
            fan_sense       => fan_sense,

            -- AXI Interface
            S_AXI_ACLK      => s_axi_aclk,
            S_AXI_ARESETN   => s_axi_aresetn,
            S_AXI_AWADDR    => s_axi_awaddr,
            S_AXI_AWPROT    => s_axi_awprot,
            S_AXI_AWVALID   => s_axi_awvalid,
            S_AXI_AWREADY   => s_axi_awready,
            S_AXI_WDATA     => s_axi_wdata,
            S_AXI_WSTRB     => s_axi_wstrb,
            S_AXI_WVALID    => s_axi_wvalid,
            S_AXI_WREADY    => s_axi_wready,
            S_AXI_BRESP     => s_axi_bresp,
            S_AXI_BVALID    => s_axi_bvalid,
            S_AXI_BREADY    => s_axi_bready,
            S_AXI_ARADDR    => s_axi_araddr,
            S_AXI_ARPROT    => s_axi_arprot,
            S_AXI_ARVALID   => s_axi_arvalid,
            S_AXI_ARREADY   => s_axi_arready,
            S_AXI_RDATA     => s_axi_rdata,
            S_AXI_RRESP     => s_axi_rresp,
            S_AXI_RVALID    => s_axi_rvalid,
            S_AXI_RREADY    => s_axi_rready
        );

    -- Add user logic here

    -- User logic ends

end rtl;
