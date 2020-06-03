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
-- Description:    Top module of Glitch Monitor IP core
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (25.05.2020)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_glitch_monitor_v1_0 is
    generic (
        -- Users to add parameters here
        C_CHANNELS            : integer range 3 to 14 := 5;
        -- User parameters ends
        -- Do not modify the parameters beyond this line


        -- Parameters of Axi Slave Bus Interface S_AXI
        C_S_AXI_DATA_WIDTH    : integer    := 32;
        C_S_AXI_ADDR_WIDTH    : integer    := 7
    );
    port (
        -- Users to add ports here

        -- I2C input (mirror) interface
        iic_0_in_sda_i  : out std_logic;
        iic_0_in_sda_o  : in  std_logic;
        iic_0_in_sda_t  : in  std_logic;
        iic_0_in_scl_i  : out std_logic;
        iic_0_in_scl_o  : in  std_logic;
        iic_0_in_scl_t  : in  std_logic;

        -- I2C output interface
        iic_0_out_sda_i : in  std_logic;
        iic_0_out_sda_o : out std_logic;
        iic_0_out_sda_t : out std_logic;
        iic_0_out_scl_i : in  std_logic;
        iic_0_out_scl_o : out std_logic;
        iic_0_out_scl_t : out std_logic;

        -- Input signals
        sig_in          : in std_logic_vector(C_CHANNELS-3 downto 0);

        -- User ports ends
        -- Do not modify the ports beyond this line

        -- Ports of Axi Slave Bus Interface S_AXI
        s_axi_aclk      : in  std_logic;
        s_axi_aresetn   : in  std_logic;
        s_axi_awaddr    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot    : in  std_logic_vector(2 downto 0);
        s_axi_awvalid   : in  std_logic;
        s_axi_awready   : out std_logic;
        s_axi_wdata     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb     : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid    : in  std_logic;
        s_axi_wready    : out std_logic;
        s_axi_bresp     : out std_logic_vector(1 downto 0);
        s_axi_bvalid    : out std_logic;
        s_axi_bready    : in  std_logic;
        s_axi_araddr    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot    : in  std_logic_vector(2 downto 0);
        s_axi_arvalid   : in  std_logic;
        s_axi_arready   : out std_logic;
        s_axi_rdata     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp     : out std_logic_vector(1 downto 0);
        s_axi_rvalid    : out std_logic;
        s_axi_rready    : in  std_logic
    );
end axi_glitch_monitor_v1_0;

architecture arch_imp of axi_glitch_monitor_v1_0 is

    ------------------------------------------------------------------------------------------------
    attribute X_INTERFACE_INFO : STRING;
    attribute X_INTERFACE_PARAMETER : STRING;

    ------------------------------------------------------------------------------------------------
    attribute X_INTERFACE_PARAMETER of iic_0_in_sda_i: signal is "XIL_INTERFACENAME IIC_0_IN";
    attribute X_INTERFACE_INFO of iic_0_in_scl_t: signal is "xilinx.com:interface:iic:1.0 IIC_0_IN SCL_T";
    attribute X_INTERFACE_INFO of iic_0_in_scl_o: signal is "xilinx.com:interface:iic:1.0 IIC_0_IN SCL_O";
    attribute X_INTERFACE_INFO of iic_0_in_scl_i: signal is "xilinx.com:interface:iic:1.0 IIC_0_IN SCL_I";
    attribute X_INTERFACE_INFO of iic_0_in_sda_t: signal is "xilinx.com:interface:iic:1.0 IIC_0_IN SDA_T";
    attribute X_INTERFACE_INFO of iic_0_in_sda_o: signal is "xilinx.com:interface:iic:1.0 IIC_0_IN SDA_O";
    attribute X_INTERFACE_INFO of iic_0_in_sda_i: signal is "xilinx.com:interface:iic:1.0 IIC_0_IN SDA_I";

    attribute X_INTERFACE_PARAMETER of iic_0_out_sda_i: signal is "XIL_INTERFACENAME IIC_0_OUT";
    attribute X_INTERFACE_INFO of iic_0_out_scl_t: signal is "xilinx.com:interface:iic:1.0 IIC_0_OUT SCL_T";
    attribute X_INTERFACE_INFO of iic_0_out_scl_o: signal is "xilinx.com:interface:iic:1.0 IIC_0_OUT SCL_O";
    attribute X_INTERFACE_INFO of iic_0_out_scl_i: signal is "xilinx.com:interface:iic:1.0 IIC_0_OUT SCL_I";
    attribute X_INTERFACE_INFO of iic_0_out_sda_t: signal is "xilinx.com:interface:iic:1.0 IIC_0_OUT SDA_T";
    attribute X_INTERFACE_INFO of iic_0_out_sda_o: signal is "xilinx.com:interface:iic:1.0 IIC_0_OUT SDA_O";
    attribute X_INTERFACE_INFO of iic_0_out_sda_i: signal is "xilinx.com:interface:iic:1.0 IIC_0_OUT SDA_I";

    ------------------------------------------------------------------------------------------------
    signal sig_tmp : std_logic_vector(C_CHANNELS-1 downto 0);

begin

    ------------------------------------------------------------------------------------------------
    -- I2C interconnect
    iic_0_in_sda_i <= iic_0_out_sda_i;
    iic_0_in_scl_i <= iic_0_out_scl_i;

    iic_0_out_sda_o <= iic_0_in_sda_o;
    iic_0_out_sda_t <= iic_0_in_sda_t;

    iic_0_out_scl_o <= iic_0_in_scl_o;
    iic_0_out_scl_t <= iic_0_in_scl_t;

    ------------------------------------------------------------------------------------------------
    sig_tmp <= sig_in & iic_0_out_sda_i & iic_0_out_scl_i;

    ------------------------------------------------------------------------------------------------
    -- Instantiation of Axi Bus Interface S_AXI
    i_glitch_monitor_S_AXI : entity work.glitch_monitor_S_AXI
        generic map (
            C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH,
            C_CHANNELS         => C_CHANNELS
        )
        port map (
            -- Input signals
            sig_in        => sig_tmp,

            -- AXI interface
            S_AXI_ACLK    => s_axi_aclk,
            S_AXI_ARESETN => s_axi_aresetn,
            S_AXI_AWADDR  => s_axi_awaddr,
            S_AXI_AWPROT  => s_axi_awprot,
            S_AXI_AWVALID => s_axi_awvalid,
            S_AXI_AWREADY => s_axi_awready,
            S_AXI_WDATA   => s_axi_wdata,
            S_AXI_WSTRB   => s_axi_wstrb,
            S_AXI_WVALID  => s_axi_wvalid,
            S_AXI_WREADY  => s_axi_wready,
            S_AXI_BRESP   => s_axi_bresp,
            S_AXI_BVALID  => s_axi_bvalid,
            S_AXI_BREADY  => s_axi_bready,
            S_AXI_ARADDR  => s_axi_araddr,
            S_AXI_ARPROT  => s_axi_arprot,
            S_AXI_ARVALID => s_axi_arvalid,
            S_AXI_ARREADY => s_axi_arready,
            S_AXI_RDATA   => s_axi_rdata,
            S_AXI_RRESP   => s_axi_rresp,
            S_AXI_RVALID  => s_axi_rvalid,
            S_AXI_RREADY  => s_axi_rready
        );

        -- Add user logic here

        -- User logic ends

end arch_imp;
