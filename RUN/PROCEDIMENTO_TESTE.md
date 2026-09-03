# Teste do esqueleto RV32I no servidor UFRGS - VCS + Verdi

O projeto contem somente a hierarquia inicial do futuro RV32I:

```text
projeto/
|-- RTL/
|   |-- riscv_system_top.sv
|   |-- riscv_core.sv
|   |-- datapath.sv
|   |-- control_unit.sv
|   |-- hazard_unit.sv
|   |-- instruction_memory.sv
|   `-- data_memory.sv
|-- tb/
|   `-- _tb_riscv_system_top.sv
|-- RUN/
|   |-- filelist.f
|   `-- PROCEDIMENTO_TESTE.md
|-- .gitignore
|-- send.ps1
`-- send.bat
```

## Objetivo

Validar a compilacao e a conectividade da hierarquia antes de implementar os
circuitos do RV32I:

```text
RTL + testbench
      |
      v
     VCS
      |
      v
    simv
      |
      v
  test.fsdb
      |
      v
    Verdi
```

O teste verifica:

- compilacao SystemVerilog;
- ordem de compilacao pelo `filelist.f`;
- passagem de `clock` e `reset` pela hierarquia;
- ida do sinal `test` ate o `datapath` e seu retorno invertido;
- execucao self-checking;
- geracao de FSDB;
- abertura da waveform no Verdi.

## 1. Sincronizar o servidor

No servidor:

```bash
cd ~/tcc
git status
git pull --ff-only origin main
```

## 2. Carregar as ferramentas

```bash
module load vcs verdi
which vcs
which verdi
```

Para sintese, quando necessario:

```bash
module load designcompiler/W-2024.09-SP5-4
```

## 3. Entrar na pasta de simulacao

```bash
cd ~/tcc/RUN
```

## 4. Conferir codificacao e filelist

O VCS usado no ambiente apresentou erro com BOM nos fontes. Os arquivos deste
pacote foram gravados sem BOM; o comentario solicitado no `datapath` usa UTF-8.

Confira:

```bash
file ../RTL/*.sv
file ../tb/_tb_riscv_system_top.sv
file filelist.f
cat -A filelist.f
```

O `filelist.f` deve aparecer assim:

```text
../tb/_tb_riscv_system_top.sv$
../RTL/riscv_system_top.sv$
../RTL/riscv_core.sv$
../RTL/datapath.sv$
../RTL/control_unit.sv$
../RTL/hazard_unit.sv$
../RTL/instruction_memory.sv$
../RTL/data_memory.sv$
```

O testbench fica primeiro, seguindo o procedimento que funcionou no ambiente.

## 5. Limpar artefatos antigos

```bash
rm -rf simv simv.daidir csrc AN.DB verdiLog ucli.key \
       comp.log sim.log test.fsdb novas.conf novas.rc novas_dump.log
```

## 6. Compilar com VCS

Como os fontes sao `.sv`, usar `-sverilog`:

```bash
vcs -full64 -sverilog \
    -f filelist.f \
    -debug_access+all \
    +memcbk \
    -kdb \
    -l comp.log
```

Nao execute `./simv` se houver erro de compilacao.

## 7. Executar

```bash
./simv | tee sim.log
```

Resultado funcional esperado:

```text
PASS: clock and reset reached the module hierarchy
PASS: test passed through the datapath and returned inverted
```

Depois confirme a waveform:

```bash
ls -lh test.fsdb
```

## 8. Abrir no Verdi

Somente depois de `test.fsdb` existir:

```bash
verdi -dbdir simv.daidir -ssf test.fsdb &
```

Se o Verdi nao abrir graficamente, verificar X11 forwarding da sessao SSH (`ssh -X` ou `ssh -Y`, conforme o ambiente).

## 9. Fluxo curto completo

```bash
cd ~/tcc/RUN
module load vcs verdi

rm -rf simv simv.daidir csrc AN.DB verdiLog ucli.key \
       comp.log sim.log test.fsdb novas.conf novas.rc novas_dump.log

vcs -full64 -sverilog -f filelist.f \
    -debug_access+all +memcbk -kdb -l comp.log

./simv | tee sim.log

verdi -dbdir simv.daidir -ssf test.fsdb &
```

## 10. Proximas etapas

Os modulos ainda nao possuem logica do processador. A implementacao do RV32I
pipeline de cinco estagios sera feita gradualmente em etapas futuras.
