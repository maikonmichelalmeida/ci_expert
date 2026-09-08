// Gerado por tools/gen_rv32i_system_program.js. Nao editar manualmente.
localparam integer PROGRAM_WORDS = 466;
localparam integer PROGRAM_BYTES = 1864;
localparam logic [31:0] BINARY_SEARCH_PC = 32'h00000334;
localparam logic [31:0] BINARY_SEARCH_END_PC = 32'h000003d4;
localparam logic [31:0] LOAD_STORE_COPY_LOAD_PC = 32'h000000d0;
localparam logic [31:0] PC_PROBE_AUIPC_PC = 32'h000005d4;
localparam logic [31:0] ALU_SIGNATURE = 32'hdffffed1;
localparam logic [31:0] BRANCH_SIGNATURE = 32'h0000003f;
localparam logic [31:0] MEMORY_SIGNATURE = 32'h00000135;
localparam logic [31:0] PASS_STATUS = 32'h600d600d;
localparam logic [31:0] FAIL_STATUS = 32'hbad0bad0;
