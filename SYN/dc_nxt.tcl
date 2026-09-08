# Fluxo minimo para Synopsys Design Compiler NXT.
# O Makefile fornece DC_MODE, DC_TOP, CLOCK_PERIOD e TARGET_LIBRARY.

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file dirname $script_dir]
set rtl_dir    [file join $root_dir RTL]
set work_dir   [file join $script_dir work]
set report_dir [file join $script_dir reports]
set output_dir [file join $script_dir output]

file mkdir $work_dir $report_dir $output_dir

set mode "check"
if {[info exists ::env(DC_MODE)]} {
    set mode $::env(DC_MODE)
}

set top_name "riscv_system_top"
if {[info exists ::env(DC_TOP)]} {
    set top_name $::env(DC_TOP)
}

set clock_period 10.0
if {[info exists ::env(CLOCK_PERIOD)]} {
    set clock_period $::env(CLOCK_PERIOD)
}

set rtl_files [list \
    [file join $rtl_dir riscv_system_top.sv] \
    [file join $rtl_dir riscv_core.sv] \
    [file join $rtl_dir datapath.sv] \
    [file join $rtl_dir pc.sv] \
    [file join $rtl_dir extend.sv] \
    [file join $rtl_dir alu.sv] \
    [file join $rtl_dir register_file.sv] \
    [file join $rtl_dir control_unit.sv] \
    [file join $rtl_dir hazard_unit.sv] \
    [file join $rtl_dir instruction_memory.sv] \
    [file join $rtl_dir data_memory.sv] \
]

set_app_var sh_continue_on_error false
define_design_lib WORK -path $work_dir
set_app_var search_path [concat $search_path [list $rtl_dir]]

# Uma sintese mapeada precisa de uma biblioteca de celulas real. O repositorio
# nao inventa essa informacao: o caminho .db deve vir pelo Makefile.
if {$mode eq "synth"} {
    if {![info exists ::env(TARGET_LIBRARY)] || $::env(TARGET_LIBRARY) eq ""} {
        puts stderr "ERRO: TARGET_LIBRARY nao foi informada."
        exit 2
    }
    set_app_var target_library [list $::env(TARGET_LIBRARY)]
    set_app_var link_library   [concat "*" $target_library]
}

puts "DC NXT: lendo RTL SystemVerilog"
analyze -format sverilog -define SYNTHESIS $rtl_files
elaborate $top_name
current_design $top_name
link

redirect -file [file join $report_dir ${top_name}_check_design.rpt] {
    set check_result [check_design]
}
redirect -file [file join $report_dir ${top_name}_hierarchy.rpt] {
    report_hierarchy
}
redirect -file [file join $report_dir ${top_name}_references.rpt] {
    report_reference
}

if {$check_result == 0} {
    puts stderr "ERRO: check_design encontrou problemas."
    exit 2
}

write -format ddc -hierarchy \
      -output [file join $output_dir ${top_name}_elaborated.ddc]

if {$mode eq "check"} {
    puts "DC NXT: elaboracao e check_design concluidos para $top_name."
    exit 0
}

# Para manter o primeiro fluxo simples, somente o clock e restringido. I/Os,
# excecoes e metas de area poderao ser acrescentados quando houver tecnologia.
create_clock -name clk -period $clock_period [get_ports clk]
compile_ultra

redirect -file [file join $report_dir ${top_name}_area.rpt] {
    report_area -hierarchy
}
redirect -file [file join $report_dir ${top_name}_timing.rpt] {
    report_timing -max_paths 10
}
redirect -file [file join $report_dir ${top_name}_qor.rpt] {
    report_qor
}

write -format ddc -hierarchy \
      -output [file join $output_dir ${top_name}_mapped.ddc]
write -format verilog -hierarchy \
      -output [file join $output_dir ${top_name}_mapped.v]
write_sdc [file join $output_dir ${top_name}_mapped.sdc]

puts "DC NXT: sintese mapeada concluida para $top_name."
exit 0
