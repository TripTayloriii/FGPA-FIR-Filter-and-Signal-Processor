## Arty S7-25 (xc7s25csga324-1) constraints for fir_uart_top
## Pin assignments follow the Digilent Arty-S7 master XDC.

## 100 MHz system clock (bank 34 is the 1.35 V DDR3 bank, hence SSTL135)
set_property -dict { PACKAGE_PIN R2  IOSTANDARD SSTL135 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5.000} [get_ports { CLK100MHZ }]
set_property INTERNAL_VREF 0.675 [get_iobanks 34]

## USB-UART bridge (names are from the PC's point of view in Digilent's XDC)
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in }]
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }]

## Red RESET button, active-low
set_property -dict { PACKAGE_PIN C18 IOSTANDARD LVCMOS33 } [get_ports { ck_rst }]

## LEDs LD2..LD5
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## These I/Os are asynchronous to the clock (they go through synchronizers or
## drive slow external devices), so there is no meaningful I/O timing.
set_false_path -from [get_ports { uart_txd_in ck_rst }]
set_false_path -to   [get_ports { uart_rxd_out led[*] }]

## Configuration
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
