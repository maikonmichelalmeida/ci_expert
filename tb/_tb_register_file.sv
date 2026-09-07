`timescale 1ns/1ps

// Preserva a verificacao da porta de escrita apos remover o acesso externo
// temporario do core. Este testbench instancia somente o Register File.
module tb_register_file;
    logic clk;
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;
    logic [31:0] rd_data;
    logic rd_we;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] x0_storage_before;

    register_file dut (
        .clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(rd_addr), .rd_data(rd_data), .rd_we(rd_we),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    always #5 clk = ~clk;

    task automatic write_register (
        input logic [4:0] address,
        input logic [31:0] data,
        input logic enable
    );
        begin
            @(negedge clk);
            rd_addr = address;
            rd_data = data;
            rd_we = enable;
            @(posedge clk);
            #1;
            rd_we = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        rd_addr = 5'd0;
        rd_data = 32'b0;
        rd_we = 1'b0;
        // A tentativa usa somente a porta real de escrita. O testbench nao
        // dirige regs[] diretamente, pois esse estado pertence ao always_ff.
        x0_storage_before = dut.regs[0];
        write_register(5'd0, 32'hffff_ffff, 1'b1);
        if ((rs1_data !== 32'b0) || (rs2_data !== 32'b0) ||
            (dut.regs[0] !== x0_storage_before))
            $fatal(1, "FAIL: x0 protection");
        $display("PASS: writes to x0 are ignored and both reads return zero");

        for (integer i = 1; i < 32; i = i + 1)
            write_register(i[4:0], 32'h1000_0000 + i, 1'b1);
        for (integer i = 1; i < 32; i = i + 1) begin
            @(negedge clk);
            rs1_addr = i[4:0];
            rs2_addr = 5'd0;
            #1;
            if ((rs1_data !== (32'h1000_0000 + i)) || (rs2_data !== 32'b0))
                $fatal(1, "FAIL: rs1 read of x%0d", i);
            rs2_addr = i[4:0];
            rs1_addr = 5'd0;
            #1;
            if ((rs2_data !== (32'h1000_0000 + i)) || (rs1_data !== 32'b0))
                $fatal(1, "FAIL: rs2 combinational read of x%0d", i);
        end
        $display("PASS: x1..x31 synchronous writes and both combinational read ports");

        write_register(5'd1, 32'hdead_beef, 1'b0);
        if (dut.regs[1] !== 32'h1000_0001)
            $fatal(1, "FAIL: rd_we=0 allowed a write");
        @(negedge clk);
        rd_addr = 5'd1;
        rd_data = 32'd7;
        rd_we = 1'b1;
        #1;
        if (dut.regs[1] !== 32'h1000_0001)
            $fatal(1, "FAIL: write happened before posedge");
        @(posedge clk);
        #1;
        if (dut.regs[1] !== 32'd7)
            $fatal(1, "FAIL: write did not happen at posedge");
        $display("PASS: write enable and posedge timing");
        $display("PASS: all Register File tests completed");
        $finish;
    end
endmodule
