# Fluxo simples de exploracao e sintese no Synopsys Design Compiler NXT.
# Todos os valores variaveis chegam pelo ambiente preparado pelo Makefile.

proc env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

set mode              [env_or_default DC_MODE check]
set top_name          [env_or_default DC_TOP riscv_system_top]
set constraint_mode   [env_or_default CONSTRAINT_MODE baseline]
set compile_style     [env_or_default COMPILE_STYLE baseline]
set clock_period      [env_or_default CLOCK_PERIOD 10.0]
set clock_uncertainty [env_or_default CLOCK_UNCERTAINTY 1.0]
set clock_latency     [env_or_default CLOCK_LATENCY 1.0]
set clock_transition  [env_or_default CLOCK_TRANSITION 0.1]
set input_delay       [env_or_default INPUT_DELAY 0.1]
set output_delay      [env_or_default OUTPUT_DELAY 0.1]
set input_transition  [env_or_default INPUT_TRANSITION 0.1]
set output_load       [env_or_default OUTPUT_LOAD 0.1]
set comb_max_delay    [env_or_default COMB_MAX_DELAY 10.0]
set timing_paths      [env_or_default TIMING_PATHS 10]

if {$mode ne "check" && $mode ne "synth"} {
    puts stderr "ERRO: DC_MODE deve ser check ou synth."
    exit 2
}

if {![info exists ::env(DC_RUN_DIR)] || $::env(DC_RUN_DIR) eq ""} {
    puts stderr "ERRO: DC_RUN_DIR nao foi informado."
    exit 2
}
set run_dir    [file normalize $::env(DC_RUN_DIR)]
set log_dir    [file join $run_dir logs]
set report_dir [file join $run_dir reports]
set output_dir [file join $run_dir output]
set work_dir   [file join $run_dir work]
file mkdir $log_dir $report_dir $output_dir $work_dir

# O filelist e criado dinamicamente pelo Makefile. Somente o TOP escolhido e
# elaborado; todos os RTLs continuam analisados para resolver dependencias.
set rtl_files [list]
if {[info exists ::env(RTL_FILELIST)] && $::env(RTL_FILELIST) ne ""} {
    set filelist_handle [open $::env(RTL_FILELIST) r]
    foreach line [split [read $filelist_handle] "\n"] {
        set rtl_file [string trim $line]
        if {$rtl_file ne "" && ![string match "#*" $rtl_file]} {
            lappend rtl_files [file normalize $rtl_file]
        }
    }
    close $filelist_handle
} elseif {[info exists ::env(RTL_FILES)] && $::env(RTL_FILES) ne ""} {
    foreach rtl_file $::env(RTL_FILES) {
        lappend rtl_files [file normalize $rtl_file]
    }
} else {
    puts stderr "ERRO: informe RTL_FILELIST ou RTL_FILES."
    exit 2
}

if {[llength $rtl_files] == 0} {
    puts stderr "ERRO: nenhum arquivo RTL foi encontrado."
    exit 2
}
foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        puts stderr "ERRO: RTL inexistente: $rtl_file"
        exit 2
    }
}

set_app_var sh_continue_on_error false
# Mantem o cache ALIB dentro do run, junto dos demais arquivos temporarios.
set_app_var alib_library_analysis_path $work_dir
define_design_lib WORK -path $work_dir

set target_library_file [env_or_default TARGET_LIBRARY ""]
set min_library_file    [env_or_default MIN_LIBRARY ""]
if {$mode eq "synth"} {
    if {$target_library_file eq ""} {
        puts stderr "ERRO: TARGET_LIBRARY nao foi informada."
        exit 2
    }
    set_app_var target_library [list $target_library_file]
    set_app_var link_library [concat "*" [list $target_library_file]]
    if {$min_library_file ne ""} {
        set_app_var link_library [concat $link_library [list $min_library_file]]
        set_min_library $target_library_file -min_version $min_library_file
    }
} else {
    # O check estrutural usa os designs analisados e a GTECH. Isso evita herdar
    # um placeholder de biblioteca que possa existir no setup global do curso.
    set_app_var link_library "*"
}

puts "DC NXT: analisando [llength $rtl_files] arquivos SystemVerilog/Verilog"
analyze -format sverilog -define SYNTHESIS $rtl_files
elaborate $top_name
current_design $top_name
link

redirect -file [file join $report_dir check_design.rpt] {
    set check_result [check_design]
}
redirect -file [file join $report_dir hierarchy.rpt] {
    report_hierarchy
}
redirect -file [file join $report_dir references.rpt] {
    report_reference
}
if {$check_result == 0} {
    puts stderr "ERRO: check_design encontrou problemas."
    exit 2
}

# Registra o contexto junto dos resultados para que duas experiencias possam
# ser comparadas sem depender do nome do diretorio.
set config_handle [open [file join $run_dir run_config.txt] w]
puts $config_handle "date=[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $config_handle "git_sha=[env_or_default GIT_SHA unknown]"
puts $config_handle "dc_version=[env_or_default DC_VERSION recorded_in_dc.log]"
puts $config_handle "mode=$mode"
puts $config_handle "top=$top_name"
puts $config_handle "target_library=$target_library_file"
puts $config_handle "min_library=$min_library_file"
puts $config_handle "constraint_mode=$constraint_mode"
puts $config_handle "clock_period=$clock_period"
puts $config_handle "clock_uncertainty=$clock_uncertainty"
puts $config_handle "clock_latency=$clock_latency"
puts $config_handle "clock_transition=$clock_transition"
puts $config_handle "input_delay=$input_delay"
puts $config_handle "output_delay=$output_delay"
puts $config_handle "input_transition=$input_transition"
puts $config_handle "output_load=$output_load"
puts $config_handle "comb_max_delay=$comb_max_delay"
puts $config_handle "compile_style=$compile_style"
puts $config_handle "timing_paths=$timing_paths"
puts $config_handle "rtl_files:"
foreach rtl_file $rtl_files {
    puts $config_handle "  $rtl_file"
}
close $config_handle

write -format ddc -hierarchy -output [file join $output_dir ${top_name}_elaborated.ddc]
if {$mode eq "check"} {
    puts "DC NXT: check concluido para $top_name em $run_dir"
    exit 0
}

if {[lsearch -exact {baseline reference custom combinational} $constraint_mode] < 0} {
    puts stderr "ERRO: CONSTRAINT_MODE invalido: $constraint_mode"
    exit 2
}
foreach numeric_value [list $clock_period $clock_uncertainty $clock_latency \
                            $clock_transition $input_delay $output_delay \
                            $input_transition $output_load $comb_max_delay] {
    if {![string is double -strict $numeric_value] || $numeric_value <= 0} {
        puts stderr "ERRO: parametro de timing invalido: $numeric_value"
        exit 2
    }
}
if {![string is integer -strict $timing_paths] || $timing_paths <= 0} {
    puts stderr "ERRO: TIMING_PATHS deve ser inteiro positivo."
    exit 2
}

if {$constraint_mode eq "combinational"} {
    set design_inputs  [all_inputs]
    set design_outputs [all_outputs]
    if {[sizeof_collection $design_inputs] == 0 ||
        [sizeof_collection $design_outputs] == 0} {
        puts stderr "ERRO: modo combinational exige entradas e saidas."
        exit 2
    }
    set_max_delay $comb_max_delay -from $design_inputs -to $design_outputs
    set_input_transition $input_transition $design_inputs
    set_load $output_load $design_outputs
} else {
    set clock_ports [get_ports -quiet clk]
    if {[sizeof_collection $clock_ports] == 0} {
        puts stderr "ERRO: TOP sem porta clk; use CONSTRAINT_MODE=combinational."
        exit 2
    }
    create_clock -name clk -period $clock_period $clock_ports

    # Baseline preserva o comportamento anterior: apenas create_clock.
    if {$constraint_mode eq "reference" || $constraint_mode eq "custom"} {
        set_clock_uncertainty $clock_uncertainty [get_clocks clk]
        set_clock_latency $clock_latency [get_clocks clk]
        set_clock_transition $clock_transition [get_clocks clk]

        set data_inputs [remove_from_collection [all_inputs] $clock_ports]
        set reset_ports [get_ports -quiet reset]
        if {[sizeof_collection $reset_ports] > 0} {
            set data_inputs [remove_from_collection $data_inputs $reset_ports]
            set_false_path -from $reset_ports
        }
        if {[sizeof_collection $data_inputs] > 0} {
            set_input_delay $input_delay -clock clk $data_inputs
            set_input_transition $input_transition $data_inputs
        }
        if {[sizeof_collection [all_outputs]] > 0} {
            set_output_delay $output_delay -clock clk [all_outputs]
            set_load $output_load [all_outputs]
        }
    }
}

if {$compile_style eq "baseline"} {
    compile_ultra
} elseif {$compile_style eq "reference"} {
    uniquify
    set_fix_multiple_port_nets -all -buffer_constants
    set_app_var verilogout_no_tri true
    compile_ultra
    change_names -rule verilog -hierarchy
} elseif {$compile_style eq "preserve"} {
    uniquify
    set_fix_multiple_port_nets -all -buffer_constants
    set_app_var verilogout_no_tri true
    compile_ultra -no_autoungroup
    change_names -rule verilog -hierarchy
} else {
    puts stderr "ERRO: COMPILE_STYLE invalido: $compile_style"
    exit 2
}

redirect -file [file join $report_dir area.rpt] {
    report_area
}
redirect -file [file join $report_dir area_hierarchy.rpt] {
    report_area -hierarchy
}
redirect -file [file join $report_dir timing.rpt] {
    report_timing -max_paths $timing_paths
}
redirect -file [file join $report_dir qor.rpt] {
    report_qor
}
redirect -file [file join $report_dir constraints.rpt] {
    report_constraint -all_violators
}
if {[llength [info commands report_resources]] > 0} {
    redirect -file [file join $report_dir resources.rpt] {
        report_resources
    }
}

write -format ddc -hierarchy -output [file join $output_dir ${top_name}_mapped.ddc]
write -format verilog -hierarchy -output [file join $output_dir ${top_name}_mapped.v]
write_sdc [file join $output_dir ${top_name}_mapped.sdc]

puts "DC NXT: sintese concluida para $top_name em $run_dir"
exit 0
