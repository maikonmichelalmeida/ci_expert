# Smoke test no servidor UFRGS - VCS + Verdi

Este pacote preserva a estrutura simples atualmente usada no repositorio:

```text
ci_expert/
|-- RTL/
|   `-- simple_adder.sv
|-- tb/
|   `-- _tb_simple_adder.sv
|-- RUN/
|   |-- filelist.f
|   `-- PROCEDIMENTO_TESTE.md
|-- .gitignore
|-- send.ps1
`-- send.bat
```

## Objetivo

Validar o fluxo minimo antes de iniciar os modulos do RV32I:

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

O VCS usado no ambiente apresentou erro com BOM/UTF-8 nos fontes.
Os arquivos deste pacote foram gravados em ASCII.

Confira:

```bash
file ../RTL/simple_adder.sv
file ../tb/_tb_simple_adder.sv
file filelist.f
cat -A filelist.f
```

O `filelist.f` deve aparecer assim:

```text
../tb/_tb_simple_adder.sv$
../RTL/simple_adder.sv$
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
PASS: 10 + 5 = 15
PASS: 200 + 100 = 300
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

## 10. Depois que este smoke test passar

Este teste nao e parte da arquitetura final do RV32I. Ele existe para provar que o ambiente funciona.

Somente depois disso vale substituir gradualmente o `simple_adder` por blocos reais, com testes unitarios separados, comecando por blocos simples como:

1. ALU;
2. register file;
3. memoria simples;
4. PC / PC+4;
5. registradores de pipeline.

Nao introduzir forwarding, stall ou flush antes de o datapath basico estar funcional.
