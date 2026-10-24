# Regenerate test vectors from the Python model, then compile and run the
# top-level testbench in Vivado xsim.
#   powershell -ExecutionPolicy Bypass -File sim\run_sim.ps1
param(
    [string]$VivadoBin = "C:\AMDDesignTools\2025.2\Vivado\bin"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $PSScriptRoot "xsim_work"     # build output (git-ignored)
$vectors = Join-Path $PSScriptRoot "vectors"
New-Item -ItemType Directory -Force $work | Out-Null

python (Join-Path $repo "scripts\fir_model.py") --gen-vectors $vectors
if ($LASTEXITCODE -ne 0) { throw "fir_model.py failed" }

Push-Location $work
try {
    & "$VivadoBin\xvlog.bat" `
        "$repo\rtl\fir595_ama_addmuladd_20s_20s_16ns_20ns_36_4_1.v" `
        "$repo\rtl\fir595.v"
    if ($LASTEXITCODE -ne 0) { throw "xvlog (Verilog) failed" }

    & "$VivadoBin\xvlog.bat" --sv `
        "$repo\rtl\uart_rx.sv" `
        "$repo\rtl\uart_tx.sv" `
        "$repo\rtl\sample_assembler.sv" `
        "$repo\rtl\fir_ctrl.sv" `
        "$repo\rtl\sample_fifo.sv" `
        "$repo\rtl\fir_uart_top.sv" `
        "$repo\sim\tb_fir_uart_top.sv"
    if ($LASTEXITCODE -ne 0) { throw "xvlog (SystemVerilog) failed" }

    & "$VivadoBin\xelab.bat" tb_fir_uart_top -s tb_sim -debug typical --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

    & "$VivadoBin\xsim.bat" tb_sim --runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
}
finally {
    Pop-Location
}
