#!/usr/bin/env bash

# Interface interativa leve para o DC NXT. Toda execucao real continua sendo
# feita pelos mesmos alvos internos do Makefile usados pela linha de comando.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RTL_DIR="$ROOT/RTL"
SYN_DIR="$ROOT/SYN"
MAKE_BIN="${MAKE:-make}"
DEFAULT_LIBRARY_DIR="/home/ciexpert/maikon.almeida/curso/03/ref/DBs"
DC_LIBRARY_DIRS="${DC_LIBRARY_DIRS:-$DEFAULT_LIBRARY_DIR}"

SESSION_STYLE="baseline"
SESSION_PATHS="10"
SELECTED=""

pause_menu() {
    echo
    read -r -p "Pressione Enter para continuar..." _ || true
}

discover_rtl_files() {
    /usr/bin/find "$RTL_DIR" -type f \( -name '*.sv' -o -name '*.v' \) -print | /usr/bin/sort
}

discover_modules() {
    local file
    while IFS= read -r file; do
        /usr/bin/awk '
            $1 == "module" {
                name = $2
                sub(/[^A-Za-z0-9_$].*/, "", name)
                if (name != "") print name
            }
        ' "$file"
    done < <(discover_rtl_files) | /usr/bin/sort -u
}

discover_libraries() {
    local directory
    local old_ifs="$IFS"
    IFS=':'
    for directory in $DC_LIBRARY_DIRS; do
        if [[ -d "$directory" ]]; then
            /usr/bin/find "$directory" -type f -name '*.db' -print
        fi
    done
    IFS="$old_ifs"
}

print_modules() {
    local modules=()
    local index
    mapfile -t modules < <(discover_modules)
    echo "Modulos encontrados em RTL/:"
    if ((${#modules[@]} == 0)); then
        echo "  nenhum modulo encontrado"
        return 1
    fi
    for index in "${!modules[@]}"; do
        printf "  %2d) %s\n" "$((index + 1))" "${modules[$index]}"
    done
}

print_libraries() {
    local libraries=()
    local index
    mapfile -t libraries < <(discover_libraries | /usr/bin/sort -u)
    echo "Bibliotecas .db encontradas em: $DC_LIBRARY_DIRS"
    if ((${#libraries[@]} == 0)); then
        echo "  nenhuma biblioteca encontrada"
        return 1
    fi
    for index in "${!libraries[@]}"; do
        printf "  %2d) %s\n" "$((index + 1))" "${libraries[$index]}"
    done
}

choose_from_array() {
    local title="$1"
    local allow_none="$2"
    shift 2
    local values=("$@")
    local answer
    local index

    SELECTED=""
    echo "$title"
    if [[ "$allow_none" == "yes" ]]; then
        echo "   0) none"
    fi
    for index in "${!values[@]}"; do
        printf "  %2d) %s\n" "$((index + 1))" "${values[$index]}"
    done

    while true; do
        read -r -p "> " answer || return 1
        answer="${answer%$'\r'}"
        if [[ "$allow_none" == "yes" && "$answer" == "0" ]]; then
            SELECTED=""
            return 0
        fi
        if [[ "$answer" =~ ^[0-9]+$ ]] &&
           ((answer >= 1 && answer <= ${#values[@]})); then
            SELECTED="${values[$((answer - 1))]}"
            return 0
        fi
        echo "Escolha invalida. Digite um numero listado."
    done
}

choose_top() {
    local modules=()
    mapfile -t modules < <(discover_modules)
    if ((${#modules[@]} == 0)); then
        echo "Erro: nenhum modulo foi encontrado em RTL/."
        return 1
    fi
    choose_from_array "Escolha TOP:" no "${modules[@]}"
}

choose_library() {
    local allow_none="$1"
    local libraries=()
    mapfile -t libraries < <(discover_libraries | /usr/bin/sort -u)
    if ((${#libraries[@]} == 0)); then
        echo "Erro: nenhuma biblioteca .db foi encontrada em $DC_LIBRARY_DIRS"
        return 1
    fi
    choose_from_array "Escolha a biblioteca:" "$allow_none" "${libraries[@]}"
}

is_positive_number() {
    local value="$1"
    [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] &&
        /usr/bin/awk -v value="$value" 'BEGIN { exit !(value > 0) }'
}

prompt_positive_number() {
    local label="$1"
    local default_value="$2"
    local answer
    while true; do
        read -r -p "$label [$default_value]: " answer || return 1
        answer="${answer%$'\r'}"
        answer="${answer:-$default_value}"
        if is_positive_number "$answer"; then
            SELECTED="$answer"
            return 0
        fi
        echo "Valor invalido. Use um numero positivo, por exemplo 10 ou 0.3."
    done
}

prompt_positive_integer() {
    local label="$1"
    local default_value="$2"
    local answer
    while true; do
        read -r -p "$label [$default_value]: " answer || return 1
        answer="${answer%$'\r'}"
        answer="${answer:-$default_value}"
        if [[ "$answer" =~ ^[1-9][0-9]*$ ]]; then
            SELECTED="$answer"
            return 0
        fi
        echo "Valor invalido. Use um numero inteiro positivo."
    done
}

choose_constraints() {
    local answer
    echo "Constraints:"
    echo "  1) Baseline"
    echo "  2) Reference / Ulisses"
    echo "  3) Custom"
    echo "  4) Combinational"
    while true; do
        read -r -p "> " answer || return 1
        case "${answer%$'\r'}" in
            1) CONSTRAINT_MODE=baseline; break ;;
            2) CONSTRAINT_MODE=reference; break ;;
            3) CONSTRAINT_MODE=custom; break ;;
            4) CONSTRAINT_MODE=combinational; break ;;
            *) echo "Escolha invalida." ;;
        esac
    done

    CLOCK_PERIOD=10.0
    CLOCK_UNCERTAINTY=1.0
    CLOCK_LATENCY=1.0
    CLOCK_TRANSITION=0.1
    INPUT_DELAY=0.1
    OUTPUT_DELAY=0.1
    INPUT_TRANSITION=0.1
    OUTPUT_LOAD=0.1
    COMB_MAX_DELAY=10.0

    if [[ "$CONSTRAINT_MODE" == "combinational" ]]; then
        prompt_positive_number "Max input-to-output delay (ns)" 10.0 || return 1
        COMB_MAX_DELAY="$SELECTED"
        prompt_positive_number "Input transition (ns)" 0.1 || return 1
        INPUT_TRANSITION="$SELECTED"
        prompt_positive_number "Output load" 0.1 || return 1
        OUTPUT_LOAD="$SELECTED"
        return 0
    fi

    prompt_positive_number "Clock period (ns)" 10.0 || return 1
    CLOCK_PERIOD="$SELECTED"
    if [[ "$CONSTRAINT_MODE" == "reference" || "$CONSTRAINT_MODE" == "custom" ]]; then
        prompt_positive_number "Clock uncertainty (ns)" 1.0 || return 1
        CLOCK_UNCERTAINTY="$SELECTED"
        prompt_positive_number "Clock latency (ns)" 1.0 || return 1
        CLOCK_LATENCY="$SELECTED"
        prompt_positive_number "Clock transition (ns)" 0.1 || return 1
        CLOCK_TRANSITION="$SELECTED"
        prompt_positive_number "Input delay (ns)" 0.1 || return 1
        INPUT_DELAY="$SELECTED"
        prompt_positive_number "Output delay (ns)" 0.1 || return 1
        OUTPUT_DELAY="$SELECTED"
        prompt_positive_number "Input transition (ns)" 0.1 || return 1
        INPUT_TRANSITION="$SELECTED"
        prompt_positive_number "Output load" 0.1 || return 1
        OUTPUT_LOAD="$SELECTED"
    fi
}

choose_compile_style() {
    local answer
    echo "Synthesis style:"
    echo "  1) Baseline - compile_ultra"
    echo "  2) Reference - uniquify/fix nets/change names"
    echo "  3) Preserve hierarchy - compile_ultra -no_autoungroup"
    while true; do
        read -r -p "Default [$SESSION_STYLE]: " answer || return 1
        answer="${answer%$'\r'}"
        if [[ -z "$answer" ]]; then
            SELECTED="$SESSION_STYLE"
            return 0
        fi
        case "$answer" in
            1) SELECTED=baseline; return 0 ;;
            2) SELECTED=reference; return 0 ;;
            3) SELECTED=preserve; return 0 ;;
            *) echo "Escolha invalida." ;;
        esac
    done
}

run_check() {
    local top
    choose_top || return
    top="$SELECTED"
    "$MAKE_BIN" --no-print-directory _dc-run DC_MODE=check TOP="$top"
}

run_synthesis() {
    local top target_library min_library compile_style run_name
    local -a args

    choose_top || return
    top="$SELECTED"
    choose_library no || return
    target_library="$SELECTED"
    echo "MIN library (opcional):"
    choose_library yes || return
    min_library="$SELECTED"
    choose_constraints || return
    choose_compile_style || return
    compile_style="$SELECTED"
    prompt_positive_integer "Number of timing paths" "$SESSION_PATHS" || return
    SESSION_PATHS="$SELECTED"

    read -r -p "Run name [automatico]: " run_name || return
    run_name="${run_name%$'\r'}"
    if [[ -n "$run_name" && ! "$run_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "Nome invalido. Use somente letras, numeros, ponto, _ ou -."
        return
    fi

    args=("$MAKE_BIN" --no-print-directory _dc-run
          DC_MODE=synth TOP="$top" LIB="$target_library"
          MIN_LIB="$min_library" CONSTRAINT_MODE="$CONSTRAINT_MODE"
          COMPILE_STYLE="$compile_style" CLOCK_PERIOD="$CLOCK_PERIOD"
          CLOCK_UNCERTAINTY="$CLOCK_UNCERTAINTY"
          CLOCK_LATENCY="$CLOCK_LATENCY"
          CLOCK_TRANSITION="$CLOCK_TRANSITION"
          INPUT_DELAY="$INPUT_DELAY" OUTPUT_DELAY="$OUTPUT_DELAY"
          INPUT_TRANSITION="$INPUT_TRANSITION" OUTPUT_LOAD="$OUTPUT_LOAD"
          COMB_MAX_DELAY="$COMB_MAX_DELAY" TIMING_PATHS="$SESSION_PATHS")
    if [[ -n "$run_name" ]]; then
        args+=(RUN_NAME="$run_name")
    fi
    "${args[@]}"
}

run_top() {
    local run_dir="$1"
    local config_file="$run_dir/run_config.txt"
    if [[ -f "$config_file" ]]; then
        /usr/bin/awk -F= '$1 == "top" {print substr($0, index($0, "=") + 1); exit}' \
            "$config_file"
    fi
}

run_label() {
    local run_dir="$1"
    local run_name top
    run_name="$(basename "$run_dir")"
    top="$(run_top "$run_dir")"

    if [[ -z "$top" ]]; then
        printf '%s [configuracao antiga ou incompleta]' "$run_name"
    elif discover_modules | /usr/bin/grep -Fxq -- "$top"; then
        printf '%s [TOP disponivel: %s]' "$run_name" "$top"
    else
        printf '%s [HISTORICO: TOP %s nao existe mais]' "$run_name" "$top"
    fi
}

discover_runs() {
    if [[ -d "$SYN_DIR/runs" ]]; then
        /usr/bin/find "$SYN_DIR/runs" -mindepth 1 -maxdepth 1 -type d -print | \
            /usr/bin/sort -r
    fi
}

print_runs() {
    local runs=()
    local index
    mapfile -t runs < <(discover_runs)
    if ((${#runs[@]} == 0)); then
        echo "Nenhum run encontrado em SYN/runs/."
        return 0
    fi

    echo "Runs encontrados:"
    for index in "${!runs[@]}"; do
        printf "  %2d) %s\n" "$((index + 1))" "$(run_label "${runs[$index]}")"
        if [[ -f "${runs[$index]}/run_config.txt" ]]; then
            /usr/bin/awk -F= '
                $1 == "date"            {date = $2}
                $1 == "git_sha"         {sha = substr($2, 1, 8)}
                $1 == "mode"            {mode = $2}
                $1 == "clock_period"    {clock_period = $2}
                $1 == "constraint_mode" {constraints = $2}
                END {
                    printf "      modo=%s | constraints=%s | clock=%s ns | data=%s | SHA=%s\n",
                           mode, constraints, clock_period, date, sha
                }
            ' "${runs[$index]}/run_config.txt"
        fi
    done
}

choose_run() {
    local runs=()
    local answer index
    mapfile -t runs < <(discover_runs)
    if ((${#runs[@]} == 0)); then
        echo "Nenhum run encontrado em SYN/runs/."
        return 1
    fi

    echo "Escolha o run:"
    for index in "${!runs[@]}"; do
        printf "  %2d) %s\n" "$((index + 1))" "$(run_label "${runs[$index]}")"
    done
    while true; do
        read -r -p "> " answer || return 1
        answer="${answer%$'\r'}"
        if [[ "$answer" =~ ^[0-9]+$ ]] &&
           ((answer >= 1 && answer <= ${#runs[@]})); then
            SELECTED="$(basename "${runs[$((answer - 1))]}")"
            return 0
        fi
        echo "Escolha invalida. Digite um numero listado."
    done
}

quick_reports() {
    local run_name run_dir
    local reports=()
    local report
    local answer
    choose_run || return
    run_name="$SELECTED"
    run_dir="$SYN_DIR/runs/$run_name"
    mapfile -t reports < <(/usr/bin/find "$run_dir/reports" -maxdepth 1 -type f -name '*.rpt' -print 2>/dev/null | /usr/bin/sort)

    echo "Relatorios de $run_name:"
    echo "  1) Quick package (check/area/timing/QoR)"
    local index
    for index in "${!reports[@]}"; do
        printf "  %2d) %s\n" "$((index + 2))" "$(basename "${reports[$index]}")"
    done
    while true; do
        read -r -p "> " answer || return
        if [[ "$answer" == "1" ]]; then
            for report in check_design.rpt area.rpt timing.rpt qor.rpt; do
                if [[ -f "$run_dir/reports/$report" ]]; then
                    echo "================ $report ================"
                    cat "$run_dir/reports/$report"
                fi
            done
            return
        fi
        if [[ "$answer" =~ ^[0-9]+$ ]] &&
           ((answer >= 2 && answer <= ${#reports[@]} + 1)); then
            cat "${reports[$((answer - 2))]}"
            return
        fi
        echo "Escolha invalida."
    done
}

show_configuration() {
    echo "Projeto:             $ROOT"
    echo "RTL:                 $RTL_DIR"
    echo "Runs:                $SYN_DIR/runs"
    echo "Bibliotecas:         $DC_LIBRARY_DIRS"
    echo "DC_ENV:              ${DC_ENV:-module load designcompiler/W-2024.09-SP5-4}"
    echo "Compile style:       $SESSION_STYLE"
    echo "Timing paths:        $SESSION_PATHS"
    echo "CLI check:           make dc-check TOP=<modulo>"
    echo "CLI synthesis:       make dc-synth TOP=<modulo> LIB=<arquivo.db>"
}

advanced_options() {
    choose_compile_style || return
    SESSION_STYLE="$SELECTED"
    prompt_positive_integer "Default timing paths" "$SESSION_PATHS" || return
    SESSION_PATHS="$SELECTED"
    echo "Opcoes da sessao atualizadas."
}

dc_menu() {
    local option
    while true; do
        if [[ -t 1 ]]; then
            clear
        fi
        echo "============================================================"
        echo "                 DC NXT EXPLORER"
        echo "============================================================"
        echo "  1) Check / inspect design"
        echo "  2) Synthesize design"
        echo "  3) Quick reports"
        echo "  4) Listar modulos/tops encontrados"
        echo "  5) Listar bibliotecas encontradas"
        echo "  6) Mostrar configuracao atual"
        echo "  7) Opcoes avancadas de sintese"
        echo
        echo "  B) Voltar"
        echo "============================================================"
        read -r -p "Escolha: " option || return
        option="${option%$'\r'}"
        case "$option" in
            1) run_check; pause_menu ;;
            2) run_synthesis; pause_menu ;;
            3) quick_reports; pause_menu ;;
            4) print_modules || true; pause_menu ;;
            5) print_libraries || true; pause_menu ;;
            6) show_configuration; pause_menu ;;
            7) advanced_options; pause_menu ;;
            b|B) return ;;
            *) echo "Opcao invalida."; pause_menu ;;
        esac
    done
}

case "${1:---menu}" in
    --menu) dc_menu ;;
    --list-modules) print_modules ;;
    --list-libraries) print_libraries ;;
    --list-runs) print_runs ;;
    --show-config) show_configuration ;;
    *)
        echo "Uso: $0 [--menu|--list-modules|--list-libraries|--list-runs|--show-config]" >&2
        exit 2
        ;;
esac
