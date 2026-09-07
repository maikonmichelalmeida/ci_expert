.DEFAULT_GOAL := menu
.RECIPEPREFIX := >
SHELL := /bin/bash

# Resolve a raiz pela localizacao deste Makefile. Assim, os alvos continuam
# funcionando mesmo quando o make e chamado de outro diretorio com -f.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RUN_DIR := $(ROOT)/RUN

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

GIT_REMOTE ?= origin
GIT_BRANCH ?= main

# A lista e obtida dos filelists existentes. Um novo filelist_<nome>.f passa
# automaticamente a aparecer no menu e na regressao completa.
TEST_NAMES := $(sort $(patsubst filelist_%.f,%,$(notdir $(wildcard $(RUN_DIR)/filelist_*.f))))

.PHONY: menu help tests show-config status update load check-filelist \
        compile rebuild run regression log complog verdi clean \
        _compile _rebuild _run _regression _verdi

# Os alvos publicos sincronizam o Git. O menu e a regressao usam os alvos com
# prefixo "_" porque a sincronizacao ja foi feita no inicio do comando.
menu: update
> @while true; do \
>   clear; \
>   echo "============================================================"; \
>   echo "              RV32I - VCS / Verdi"; \
>   echo "============================================================"; \
>   echo "  1) Compilar e executar o teste atual"; \
>   echo "  2) Escolher e executar um teste"; \
>   echo "  3) Abrir o Verdi"; \
>   echo "  4) Ver o log de simulacao"; \
>   echo "  5) Recompilar do zero"; \
>   echo "  6) Listar testes"; \
>   echo "  7) Executar a regressao completa"; \
>   echo "  8) Ver o estado do Git"; \
>   echo "  9) Atualizar a branch pelo Git"; \
>   echo " Enter) Sair"; \
>   echo "============================================================"; \
>   echo " Teste atual: $(if $(strip $(TEST)),$(TEST),default)"; \
>   if ! read -r -p "Escolha [1-9, Enter para sair]: " option; then echo; break; fi; \
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
>     3) $(MAKE) --no-print-directory _verdi TEST="$(TEST)";; \
>     4) $(MAKE) --no-print-directory log TEST="$(TEST)";; \
>     5) $(MAKE) --no-print-directory _rebuild TEST="$(TEST)";; \
>     6) $(MAKE) --no-print-directory tests;; \
>     7) $(MAKE) --no-print-directory _regression;; \
>     8) $(MAKE) --no-print-directory status;; \
>     9) $(MAKE) --no-print-directory update;; \
>     "") break;; \
>     *) echo "Opcao invalida.";; \
>   esac; \
>   echo; read -r -p "Pressione Enter para continuar..." || break; \
> done

help:
> @echo "Uso principal:"
> @echo "  make                        Atualiza o Git e abre o menu"
> @echo "  make run                    Compila e executa o teste default"
> @echo "  make run TEST=alu           Compila e executa filelist_alu.f"
> @echo "  make compile TEST=jalr      Somente compila o teste JALR"
> @echo "  make regression             Executa o teste default e todos os testes nomeados"
> @echo "  make verdi TEST=fetch       Abre a forma de onda do teste Fetch"
> @echo "  make clean                  Remove produtos gerados, preservando os logs"
> @echo "  make update                 Atualiza $(GIT_REMOTE)/$(GIT_BRANCH) manualmente"
> @echo
> @echo "Opcoes uteis:"
> @echo "  FILELIST=<arquivo.f>        Escolhe manualmente um filelist dentro de RUN/"
> @echo "  VCS_EXTRA_FLAGS='<flags>'   Acrescenta opcoes na compilacao"
> @echo "  VCS_ENV='<comando>'         Ajusta o comando de preparacao do ambiente VCS"
> @echo "  VERDI_ENV='<comando>'       Ajusta o comando de preparacao do ambiente Verdi"

tests:
> @echo "Teste default: filelist.f"
> @echo "Testes nomeados:"
> @for test in $(TEST_NAMES); do echo "  $$test"; done

show-config:
> @echo "ROOT            = $(ROOT)"
> @echo "RUN_DIR         = $(RUN_DIR)"
> @echo "TEST            = $(if $(strip $(TEST)),$(TEST),default)"
> @echo "FILELIST        = $(FILELIST)"
> @echo "COMP_LOG        = $(COMP_LOG)"
> @echo "SIM_LOG         = $(SIM_LOG)"
> @echo "FSDB            = $(FSDB)"
> @echo "VCS_COMMON_FLAGS= $(VCS_COMMON_FLAGS)"
> @echo "VCS_EXTRA_FLAGS = $(VCS_EXTRA_FLAGS)"

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
> @cd "$(RUN_DIR)" && bash -lc 'set -o pipefail; $(VCS_ENV); ./simv | tee "$(SIM_LOG)"; exit $${PIPESTATUS[0]}'

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
