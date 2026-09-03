# Esqueleto RISC-V RV32I

Estrutura inicial de um futuro processador RISC-V RV32I com pipeline de cinco
estagios. Nesta etapa, os modulos sao apenas esqueletos: nao ha circuitos nem
logica de processador implementados.

O `clock` e o `reset` percorrem toda a hierarquia. Um sinal `test` sai do
testbench, chega ao `datapath`, e retorna invertido para validar a conectividade.

Para compilar e executar no servidor UFRGS com VCS e Verdi, consulte
`RUN/PROCEDIMENTO_TESTE.md`.
