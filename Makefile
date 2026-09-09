.DEFAULT_GOAL := menu
.RECIPEPREFIX := >
SHELL := /bin/bash

# Resolve a raiz pela localizacao deste Makefile. Assim, os alvos continuam
# funcionando mesmo quando o make e chamado de outro diretorio com -f.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RUN_DIR := $(ROOT)/RUN
SYN_DIR := $(ROOT)/SYN
TOOLS_DIR := $(ROOT)/tools
DC_EXPLORER := $(TOOLS_DIR)/dc_explorer.sh

TEST ?=
FILELIST ?= $(if $(strip $(TEST)),filelist_$(TEST).f,filelist.f)
COMP_LOG ?= $(if $(strip $(TEST)),comp_$(TEST).log,comp.log)
SIM_LOG ?= $(if $(strip $(TEST)),sim_$(TEST).log,sim.log)
FSDB ?= test.fsdb

VCS_BIN ?= vcs
VERDI_BIN ?= verdi
VCS_ENV ?= module load vcs
VERDI_ENV ?= module load vcs verdi
VCS_COMMON_FLAGS ?= -full64 -sverilog -debug_access+all +memcbk -kdb
VCS_EXTRA_FLAGS ?=
VCS_FLAGS = $(VCS_COMMON_FLAGS) $(VCS_EXTRA_FLAGS) -f "$(FILELIST)" -o simv -l "$(COMP_LOG)"

DC_BIN ?= dc_shell
DC_ENV ?= module load designcompiler/W-2024.09-SP5-4
DC_CHECK_TOP ?= riscv_system_top
SYN_TOP ?= riscv_core
TOP ?=
CLOCK_PERIOD ?= 10.0
TARGET_LIBRARY ?=
LIB ?=
MIN_LIB ?=
DC_LIBRARY_DIRS ?= /home/ciexpert/maikon.almeida/curso/03/ref/DBs
CONSTRAINT_MODE ?= baseline
CLOCK_UNCERTAINTY ?= 1.0
CLOCK_LATENCY ?= 1.0
CLOCK_TRANSITION ?= 0.1
INPUT_DELAY ?= 0.1
OUTPUT_DELAY ?= 0.1
INPUT_TRANSITION ?= 0.1
OUTPUT_LOAD ?= 0.1
COMB_MAX_DELAY ?= 10.0
COMPILE_STYLE ?= baseline
TIMING_PATHS ?= 10
RUN_NAME ?=
RTL_FILELIST ?=

GIT_REMOTE ?= origin
GIT_BRANCH ?= main
SYSTEM_TEST := rv32i_system_program

# A lista e obtida dos filelists existentes. Um novo filelist_<nome>.f passa
# automaticamente a aparecer no menu e na regressao completa.
TEST_NAMES := $(sort $(patsubst filelist_%.f,%,$(notdir $(wildcard $(RUN_DIR)/filelist_*.f))))

.PHONY: menu rtl-menu dc-menu git-menu help tests show-config status update load check-filelist \
        compile rebuild run system regression log complog verdi clean \
        dc-check dc-synth synth dc-modules dc-libs dc-runs clean-synth \
        _menu _rtl-menu _git-menu _compile _rebuild _run _regression _verdi _dc-run

# O menu principal atualiza o Git uma unica vez. Os submenus usam alvos com
# prefixo "_" e nao repetem pulls silenciosos durante a mesma sessao.
menu: update _menu

_menu:
> @while true; do \
>   [ ! -t 1 ] || clear; \
>   echo "============================================================"; \
>   echo "                 CI EXPERT - PROJECT"; \
>   echo "============================================================"; \
>   echo "  1) RTL / VCS / Verdi"; \
>   echo "  2) DC NXT / Synthesis Explorer"; \
>   echo "  3) Git status / update"; \
>   echo "  4) Help"; \
>   echo; \
>   echo " Enter) Exit"; \
>   echo "============================================================"; \
>   if ! read -r -p "Escolha [1-4, Enter para sair]: " option; then echo; break; fi; \
>   option="$${option%$$'\r'}"; \
>   case "$$option" in \
>     1) $(MAKE) --no-print-directory _rtl-menu;; \
>     2) $(MAKE) --no-print-directory dc-menu;; \
>     3) $(MAKE) --no-print-directory _git-menu;; \
>     4) $(MAKE) --no-print-directory help; echo; read -r -p "Pressione Enter para continuar..." || break;; \
>     "") break;; \
>     *) echo "Opcao invalida."; read -r -p "Pressione Enter para continuar..." || break;; \
>   esac; \
> done

rtl-menu: update _rtl-menu

_rtl-menu:
> @while true; do \
>   [ ! -t 1 ] || clear; \
>   echo "============================================================"; \
>   echo "                 RTL / VCS / VERDI"; \
>   echo "============================================================"; \
>   echo "  1) Compilar e executar o teste atual"; \
>   echo "  2) Escolher e executar um teste"; \
>   echo "  3) Executar o programa RV32I end-to-end"; \
>   echo "  4) Executar a regressao completa"; \
>   echo "  5) Abrir o Verdi"; \
>   echo "  6) Ver o log de simulacao"; \
>   echo "  7) Ver o log de compilacao"; \
>   echo "  8) Recompilar do zero"; \
>   echo "  9) Listar testes"; \
>   echo; \
>   echo "  B) Voltar"; \
>   echo "============================================================"; \
>   echo " Teste atual: $(if $(strip $(TEST)),$(TEST),default)"; \
>   if ! read -r -p "Escolha [1-9, B]: " option; then echo; break; fi; \
>   option="$${option%$$'\r'}"; \
>   case "$$option" in \
>     1) $(MAKE) --no-print-directory _run TEST="$(TEST)";; \
>     2) \
>       tests=($(TEST_NAMES)); \
>       echo; \
>       for i in "$${!tests[@]}"; do printf "  %2d) %s\n" "$$((i + 1))" "$${tests[$$i]}"; done; \
>       echo; \
>       if ! read -r -p "Numero do teste: " choice; then echo; break; fi; \
>       choice="$${choice%$$'\r'}"; \
>       if [[ "$$choice" =~ ^[0-9]+$$ ]] && (( choice >= 1 && choice <= $${#tests[@]} )); then \
>         selected="$${tests[$$((choice - 1))]}"; \
>         $(MAKE) --no-print-directory _run TEST="$$selected"; \
>       else \
>         echo "Escolha invalida."; \
>       fi;; \
>     3) $(MAKE) --no-print-directory _run TEST="$(SYSTEM_TEST)";; \
>     4) $(MAKE) --no-print-directory _regression;; \
>     5) $(MAKE) --no-print-directory _verdi TEST="$(TEST)";; \
>     6) $(MAKE) --no-print-directory log TEST="$(TEST)";; \
>     7) $(MAKE) --no-print-directory complog TEST="$(TEST)";; \
>     8) $(MAKE) --no-print-directory _rebuild TEST="$(TEST)";; \
>     9) $(MAKE) --no-print-directory tests;; \
>     b|B) break;; \
>     *) echo "Opcao invalida.";; \
>   esac; \
>   echo; read -r -p "Pressione Enter para continuar..." || break; \
> done

git-menu: update _git-menu

_git-menu:
> @while true; do \
>   echo "1) Git status"; \
>   echo "2) Git fetch + pull --ff-only"; \
>   echo "B) Voltar"; \
>   if ! read -r -p "Escolha: " option; then echo; break; fi; \
>   case "$${option%$$'\r'}" in \
>     1) $(MAKE) --no-print-directory status;; \
>     2) $(MAKE) --no-print-directory update;; \
>     b|B) break;; \
>     *) echo "Opcao invalida.";; \
>   esac; \
> done

help:
> @echo "Uso principal:"
> @echo "  make                        Atualiza o Git uma vez e abre o menu principal"
> @echo "  make rtl-menu               Abre diretamente o submenu RTL"
> @echo "  make dc-menu                Abre diretamente o DC NXT Explorer"
> @echo "  make run                    Compila e executa o teste default"
> @echo "  make run TEST=alu           Compila e executa filelist_alu.f"
> @echo "  make system                 Executa o programa RV32I end-to-end"
> @echo "  make compile TEST=jalr      Somente compila o teste JALR"
> @echo "  make regression             Executa o teste default e todos os testes nomeados"
> @echo "  make verdi TEST=fetch       Abre a forma de onda do teste Fetch"
> @echo "  make dc-check TOP=alu       Analisa todos os RTLs e elabora o TOP escolhido"
> @echo "  make dc-synth TOP=riscv_core LIB=/caminho/celulas.db"
> @echo "                              Sintetiza e salva um novo run em SYN/runs"
> @echo "  make synth ...              Alias compativel para make dc-synth"
> @echo "  make dc-modules             Lista modulos descobertos em RTL/"
> @echo "  make dc-libs                Lista bibliotecas .db realmente encontradas"
> @echo "  make dc-runs                Lista runs e suas configuracoes"
> @echo "  make clean                  Remove produtos gerados, preservando os logs"
> @echo "  make clean-synth RUN_NAME=x Remove somente um run de sintese"
> @echo "  make update                 Atualiza $(GIT_REMOTE)/$(GIT_BRANCH) manualmente"
> @echo
> @echo "Opcoes uteis:"
> @echo "  FILELIST=<arquivo.f>        Escolhe manualmente um filelist dentro de RUN/"
> @echo "  VCS_EXTRA_FLAGS='<flags>'   Acrescenta opcoes na compilacao"
> @echo "  VCS_ENV='<comando>'         Ajusta o comando de preparacao do ambiente VCS"
> @echo "  VERDI_ENV='<comando>'       Ajusta o comando de preparacao do ambiente Verdi"
> @echo "  DC_ENV='<comando>'          Ajusta o module load do DC NXT"
> @echo "  DC_LIBRARY_DIRS='dir:dir'   Diretorios pesquisados por bibliotecas .db"
> @echo "  CONSTRAINT_MODE=<modo>      baseline, reference, custom ou combinational"
> @echo "  COMPILE_STYLE=<estilo>      baseline, reference ou preserve"
> @echo "  CLOCK_PERIOD=<ns>           Periodo do clock; padrao 10.0 ns"

tests:
> @echo "Teste default: filelist.f"
> @echo "Testes nomeados:"
> @for test in $(TEST_NAMES); do \
>   if [ "$$test" = "$(SYSTEM_TEST)" ]; then \
>     echo "  $$test  [programa completo end-to-end]"; \
>   else \
>     echo "  $$test"; \
>   fi; \
> done

show-config:
> @echo "ROOT            = $(ROOT)"
> @echo "RUN_DIR         = $(RUN_DIR)"
> @echo "SYN_DIR         = $(SYN_DIR)"
> @echo "TEST            = $(if $(strip $(TEST)),$(TEST),default)"
> @echo "FILELIST        = $(FILELIST)"
> @echo "COMP_LOG        = $(COMP_LOG)"
> @echo "SIM_LOG         = $(SIM_LOG)"
> @echo "FSDB            = $(FSDB)"
> @echo "VCS_COMMON_FLAGS= $(VCS_COMMON_FLAGS)"
> @echo "VCS_EXTRA_FLAGS = $(VCS_EXTRA_FLAGS)"
> @echo "DC_BIN          = $(DC_BIN)"
> @echo "TOP             = $(if $(strip $(TOP)),$(TOP),selecionado pelo alvo/menu)"
> @echo "CLOCK_PERIOD    = $(CLOCK_PERIOD) ns"
> @echo "CONSTRAINT_MODE = $(CONSTRAINT_MODE)"
> @echo "COMPILE_STYLE   = $(COMPILE_STYLE)"
> @echo "LIB             = $(if $(strip $(LIB)),$(LIB),$(if $(strip $(TARGET_LIBRARY)),$(TARGET_LIBRARY),nao informada))"
> @echo "MIN_LIB         = $(if $(strip $(MIN_LIB)),$(MIN_LIB),none)"
> @echo "LIBRARY_DIRS    = $(DC_LIBRARY_DIRS)"

status:
> @git -C "$(ROOT)" status -sb

# O servidor e o ambiente de testes e deve iniciar sempre sincronizado com a
# branch publica. O pull --ff-only atualiza sem criar merge automatico.
update:
> @current_branch="$$(git -C "$(ROOT)" branch --show-current)"; \
> if [ "$$current_branch" != "$(GIT_BRANCH)" ]; then \
>   echo "Erro: branch atual e '$$current_branch'; esperado '$(GIT_BRANCH)'."; \
>   exit 1; \
> fi; \
> git -C "$(ROOT)" fetch --prune "$(GIT_REMOTE)"; \
> git -C "$(ROOT)" pull --ff-only "$(GIT_REMOTE)" "$(GIT_BRANCH)"

load:
> @bash -lc 'set -e; $(VERDI_ENV); command -v $(VCS_BIN); command -v $(VERDI_BIN); $(VCS_BIN) -ID'

check-filelist:
> @if [ ! -f "$(RUN_DIR)/$(FILELIST)" ]; then \
>   echo "Erro: filelist nao encontrado: $(RUN_DIR)/$(FILELIST)"; \
>   echo "Use 'make tests' para ver os testes disponiveis."; \
>   exit 1; \
> fi

compile: update _compile

_compile: check-filelist
> @echo "Compilando o teste $(if $(strip $(TEST)),$(TEST),default) com $(FILELIST)..."
> @cd "$(RUN_DIR)" && bash -lc 'set -e; $(VCS_ENV); command -v $(VCS_BIN) >/dev/null || { echo "Erro: $(VCS_BIN) nao foi encontrado."; exit 1; }; $(VCS_BIN) $(VCS_FLAGS)'

rebuild: update _rebuild

_rebuild: clean _compile

run: update _run

_run: _compile
> @echo "Executando a simulacao; log em RUN/$(SIM_LOG)..."
> @cd "$(RUN_DIR)" && bash -lc 'set -o pipefail; $(VCS_ENV); ./simv | tee "$(SIM_LOG)"; status=$${PIPESTATUS[0]}; if grep -Eq "^Fatal:|(^|[[:space:]])FAIL:" "$(SIM_LOG)"; then echo "Erro: a simulacao registrou uma falha em $(SIM_LOG)."; status=1; fi; exit $$status'

# Atalho para a demonstracao completa. Ele reutiliza exatamente o fluxo normal
# de compilacao/simulacao e, portanto, tambem gera logs com o nome do teste.
system: update
> @$(MAKE) --no-print-directory _run TEST="$(SYSTEM_TEST)"

# O menu interativo e a CLI convergem em _dc-run. Somente os alvos publicos
# fazem update; uma sessao aberta pelo menu principal nao repete git pull.
dc-menu:
> @DC_LIBRARY_DIRS="$(DC_LIBRARY_DIRS)" DC_ENV="$(DC_ENV)" \
>   bash "$(DC_EXPLORER)" --menu

dc-modules:
> @bash "$(DC_EXPLORER)" --list-modules

dc-libs:
> @DC_LIBRARY_DIRS="$(DC_LIBRARY_DIRS)" bash "$(DC_EXPLORER)" --list-libraries

dc-check: update
> @$(MAKE) --no-print-directory _dc-run DC_MODE=check \
>   TOP="$(if $(strip $(TOP)),$(TOP),$(DC_CHECK_TOP))"

dc-synth synth: update
> @$(MAKE) --no-print-directory _dc-run DC_MODE=synth \
>   TOP="$(if $(strip $(TOP)),$(TOP),$(SYN_TOP))"

_dc-run:
> @set -e; \
> mode="$(DC_MODE)"; \
> top="$(TOP)"; \
> library="$(if $(strip $(LIB)),$(LIB),$(TARGET_LIBRARY))"; \
> if [ "$$mode" != "check" ] && [ "$$mode" != "synth" ]; then \
>   echo "Erro: DC_MODE deve ser check ou synth."; exit 1; \
> fi; \
> if [ -z "$$top" ] || ! [[ "$$top" =~ ^[A-Za-z_][A-Za-z0-9_]*$$ ]]; then \
>   echo "Erro: TOP invalido: $$top"; exit 1; \
> fi; \
> if [ "$$mode" = "synth" ] && [ -z "$$library" ]; then \
>   echo "Erro: informe LIB=/caminho/celulas.db"; exit 1; \
> fi; \
> if [ -n "$$library" ] && [ ! -f "$$library" ]; then \
>   echo "Erro: biblioteca nao encontrada: $$library"; exit 1; \
> fi; \
> if [ -n "$(MIN_LIB)" ] && [ ! -f "$(MIN_LIB)" ]; then \
>   echo "Erro: MIN library nao encontrada: $(MIN_LIB)"; exit 1; \
> fi; \
> run_name="$(RUN_NAME)"; \
> if [ -z "$$run_name" ]; then \
>   run_name="$$(date +%Y%m%d_%H%M%S_%N)_$${top}_$${mode}"; \
> fi; \
> if ! [[ "$$run_name" =~ ^[A-Za-z0-9_.-]+$$ ]]; then \
>   echo "Erro: RUN_NAME contem caracteres invalidos."; exit 1; \
> fi; \
> run_dir="$(SYN_DIR)/runs/$$run_name"; \
> if [ -e "$$run_dir" ]; then \
>   echo "Erro: o run ja existe e nao sera sobrescrito: $$run_dir"; exit 1; \
> fi; \
> mkdir -p "$$run_dir/logs" "$$run_dir/reports" "$$run_dir/output" "$$run_dir/work"; \
> generated_filelist="$$run_dir/rtl_files.f"; \
> if [ -n "$(RTL_FILELIST)" ]; then \
>   if [ ! -f "$(RTL_FILELIST)" ]; then echo "Erro: RTL_FILELIST inexistente."; exit 1; fi; \
>   cp "$(RTL_FILELIST)" "$$generated_filelist"; \
> else \
>   /usr/bin/find "$(ROOT)/RTL" -type f \( -name '*.sv' -o -name '*.v' \) -print | /usr/bin/sort > "$$generated_filelist"; \
> fi; \
> if [ ! -s "$$generated_filelist" ]; then \
>   echo "Erro: nenhum RTL foi encontrado."; exit 1; \
> fi; \
> git_sha="$$(git -C "$(ROOT)" rev-parse HEAD)"; \
> echo "Run: $$run_dir"; \
> cd "$$run_dir/work"; \
> bash -lc 'set -o pipefail; $(DC_ENV); command -v $(DC_BIN) >/dev/null || { echo "Erro: $(DC_BIN) nao foi encontrado. Ajuste DC_ENV ou DC_BIN."; exit 1; }; dc_version="$$( $(DC_BIN) -version 2>&1 | /usr/bin/awk '\''/^dc_shell version/{print; exit}'\'' || true )"; export DC_MODE="'"$$mode"'" DC_TOP="'"$$top"'" DC_RUN_DIR="'"$$run_dir"'" RTL_FILELIST="'"$$generated_filelist"'" GIT_SHA="'"$$git_sha"'" DC_VERSION="$$dc_version" TARGET_LIBRARY="'"$$library"'" MIN_LIBRARY="$(MIN_LIB)" CONSTRAINT_MODE="$(CONSTRAINT_MODE)" COMPILE_STYLE="$(COMPILE_STYLE)" CLOCK_PERIOD="$(CLOCK_PERIOD)" CLOCK_UNCERTAINTY="$(CLOCK_UNCERTAINTY)" CLOCK_LATENCY="$(CLOCK_LATENCY)" CLOCK_TRANSITION="$(CLOCK_TRANSITION)" INPUT_DELAY="$(INPUT_DELAY)" OUTPUT_DELAY="$(OUTPUT_DELAY)" INPUT_TRANSITION="$(INPUT_TRANSITION)" OUTPUT_LOAD="$(OUTPUT_LOAD)" COMB_MAX_DELAY="$(COMB_MAX_DELAY)" TIMING_PATHS="$(TIMING_PATHS)"; $(DC_BIN) -f "$(SYN_DIR)/dc_nxt.tcl" | tee "'"$$run_dir"'/logs/dc.log"; exit $${PIPESTATUS[0]}'

dc-runs:
> @bash "$(DC_EXPLORER)" --list-runs

clean-synth:
> @set -e; \
> if [ -z "$(RUN_NAME)" ] || ! [[ "$(RUN_NAME)" =~ ^[A-Za-z0-9_.-]+$$ ]]; then \
>   echo "Erro: informe um RUN_NAME valido para remover somente aquele run."; exit 1; \
> fi; \
> base="$$(/usr/bin/realpath -m "$(SYN_DIR)/runs")"; \
> target="$$(/usr/bin/realpath -m "$(SYN_DIR)/runs/$(RUN_NAME)")"; \
> case "$$target" in "$$base"/*) ;; *) echo "Erro: destino fora de SYN/runs."; exit 1;; esac; \
> if [ ! -d "$$target" ]; then echo "Erro: run nao encontrado: $$target"; exit 1; fi; \
> rm -rf -- "$$target"; \
> echo "Run removido: $$target"

# Executa primeiro a integracao default e depois cada filelist_<teste>.f.
# O primeiro erro interrompe a regressao e preserva o log que explica a falha.
regression: update _regression

_regression:
> @set -e; \
> echo "===== teste default ====="; \
> $(MAKE) --no-print-directory _run TEST= FILELIST=filelist.f COMP_LOG=comp.log SIM_LOG=sim.log FSDB=test.fsdb; \
> for test in $(TEST_NAMES); do \
>   echo "===== teste $$test ====="; \
>   $(MAKE) --no-print-directory _run TEST="$$test"; \
> done; \
> echo "===== regressao concluida com sucesso ====="

log:
> @if [ ! -f "$(RUN_DIR)/$(SIM_LOG)" ]; then \
>   echo "Log nao encontrado: $(RUN_DIR)/$(SIM_LOG)"; \
>   exit 1; \
> fi
> @cat "$(RUN_DIR)/$(SIM_LOG)"

complog:
> @if [ ! -f "$(RUN_DIR)/$(COMP_LOG)" ]; then \
>   echo "Log nao encontrado: $(RUN_DIR)/$(COMP_LOG)"; \
>   exit 1; \
> fi
> @less -R "$(RUN_DIR)/$(COMP_LOG)"

verdi: update _verdi

_verdi: check-filelist
> @if [ ! -f "$(RUN_DIR)/$(FSDB)" ] || [ ! -d "$(RUN_DIR)/simv.daidir" ]; then \
>   echo "Waveform ausente; executando a simulacao primeiro..."; \
>   $(MAKE) --no-print-directory _run TEST="$(TEST)" FILELIST="$(FILELIST)" \
>     COMP_LOG="$(COMP_LOG)" SIM_LOG="$(SIM_LOG)" FSDB="$(FSDB)"; \
> fi
> @cd "$(RUN_DIR)" && bash -lc 'set -e; $(VERDI_ENV); command -v $(VERDI_BIN) >/dev/null || { echo "Erro: $(VERDI_BIN) nao foi encontrado."; exit 1; }; exec $(VERDI_BIN) -dbdir simv.daidir -ssf "$(FSDB)"' >/dev/null 2>&1 &

# Remove somente arquivos gerados dentro de RUN/. Os logs ficam guardados para
# facilitar a investigacao de uma regressao que tenha falhado.
clean:
> @echo "Removendo produtos de compilacao e formas de onda de RUN/..."
> @rm -rf "$(RUN_DIR)/simv" \
>          "$(RUN_DIR)"/simv*.daidir \
>          "$(RUN_DIR)/csrc" \
>          "$(RUN_DIR)/ucli.key" \
>          "$(RUN_DIR)/verdiLog" \
>          "$(RUN_DIR)/AN.DB" \
>          "$(RUN_DIR)/DVEfiles" \
>          "$(RUN_DIR)"/*.fsdb \
>          "$(RUN_DIR)"/*.vpd \
>          "$(RUN_DIR)"/novas.*
> @echo "Limpeza concluida. Arquivos *.log foram preservados."
