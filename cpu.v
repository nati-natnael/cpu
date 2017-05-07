//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
// Company:
// Engineer:
//
// Create Date:    11:00:54 02/23/2017
// Design Name:
// Module Name:    cpu
// Project Name:
// Target Devices:
// Tool versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

//the CPU module from 4.13.4 of the textbook from the online companion material
//The initial register and memory state are read from .dat files and the
//resulting register and memory state are each printed into corresponding .dat
//files
//TODO
//implement three other instructions, cmov, jrt and lwcab and also
//a 'taken' branch predictor

module CPU (clock);
   parameter LW = 6'b100_011, SW = 6'b101_011, BEQ = 6'b000_100, JRT = 6'b011_110, LWCAB = 6'b011_111;
   parameter no_op = 32'b0000000_0000000_0000000_0000000, ALUop = 6'b0;

   integer fd,code,str;
   input clock;

   reg[31:0] PC, Regs[0:31], IMemory[0:1023], DMemory[0:1023], // separate memories
             IFIDIR, IDEXA, IDEXB, IDEXIR, EXMEMIR, EXMEMB, // pipeline registers
             EXMEMALUOut, MEMWBValue, MEMWBIR; // pipeline registers
   wire [4:0] IDEXrs, IDEXrt, EXMEMrd, MEMWBrd, MEMWBrt; //hold register fields
   wire [5:0] IFIDop, EXMEMop, MEMWBop, IDEXop; //Hold opcodes
   wire [31:0] Ain, Bin;


   //declare the bypass signals
   wire nottaken, stall, bypassAfromMEM, bypassAfromALUinWB,bypassBfromMEM, bypassBfromALUinWB,
        bypassAfromLWinWB, bypassBfromLWinWB;

   assign IDEXrs = IDEXIR[25:21];  
   assign IDEXrt = IDEXIR[20:16];
   assign IDEXop = IDEXIR[31:26];
  
   assign EXMEMop = EXMEMIR[31:26]; 
   assign EXMEMrd = EXMEMIR[15:11];

   assign MEMWBrd = MEMWBIR[15:11]; 
   assign MEMWBrt = MEMWBIR[20:16];
   assign MEMWBop = MEMWBIR[31:26];  

   // The bypass to input A from the MEM stage for an ALU operation
   assign bypassAfromMEM = (IDEXrs == EXMEMrd) & (IDEXrs != 0) & (EXMEMop == ALUop); // yes, bypass

   // The bypass to input B from the MEM stage for an ALU operation
   assign bypassBfromMEM = (IDEXrt == EXMEMrd) & (IDEXrt != 0) & (EXMEMop == ALUop); // yes, bypass

   // The bypass to input A from the WB stage for an ALU operation
   assign bypassAfromALUinWB =( IDEXrs == MEMWBrd) & (IDEXrs!=0) & (MEMWBop==ALUop);

   // The bypass to input B from the WB stage for an ALU operation
   assign bypassBfromALUinWB = (IDEXrt == MEMWBrd) & (IDEXrt!=0) & (MEMWBop==ALUop);

   // The bypass to input A from the WB stage for an LW operation
   assign bypassAfromLWinWB = (IDEXrs == MEMWBIR[20:16]) & (IDEXrs!=0) & (MEMWBop==LW);

   // The bypass to input B from the WB stage for an LW operation
   assign bypassBfromLWinWB = (IDEXrt == MEMWBIR[20:16]) & (IDEXrt!=0) & (MEMWBop==LW);

   // The A input to the ALU is bypassed from MEM if there is a bypass there,
   // Otherwise from WB if there is a bypass there, and otherwise comes from the IDEX register
   assign Ain = bypassAfromMEM ? EXMEMALUOut :
               (bypassAfromALUinWB | bypassAfromLWinWB) ? MEMWBValue : IDEXA;

   // The B input to the ALU is bypassed from MEM if there is a bypass there,
   // Otherwise from WB if there is a bypass there, and otherwise comes from the IDEX register
   assign Bin = bypassBfromMEM? EXMEMALUOut :
               (bypassBfromALUinWB | bypassBfromLWinWB)? MEMWBValue: IDEXB;

   // The signal for detecting a stall based on the use of a result from LW
   assign stall = ((EXMEMIR[31:26] == LW) | (EXMEMIR[31:26] == LWCAB)) 					&& // source instruction is a load
	           ((((IDEXop == LW)|(IDEXop == SW)) && (IDEXrs == EXMEMIR[20:16])) 			|  // stall for address calc
                   ((IDEXop == ALUop) && ((IDEXrs == EXMEMIR[20:16]) | (IDEXrt == EXMEMIR[20:16])))	|  // ALU use
		   ((IDEXop == LWCAB) && ((IDEXrs == EXMEMIR[25:21]) | (IDEXrt == EXMEMIR[25:21])))); 	   // load with bound check use

   //Signal for a taken branch: instruction is BEQ and registers are equal
   assign nottaken = (IFIDIR[31:26] == BEQ) && (Regs[IFIDIR[25:21]] != Regs[IFIDIR[20:16]]);
   
   reg [10:0] i; //used to initialize registers

   initial begin
      #1 //delay of 1, wait for the input ports to initialize
      PC = 0;
      IFIDIR = no_op; IDEXIR = no_op; EXMEMIR = no_op; MEMWBIR = no_op; // put no_ops in pipeline registers

      for (i = 0; i <= 31; i = i + 1) Regs[i] = i; //initialize registers -- just so they aren't don't cares
      for (i = 0; i <= 1023; i = i + 1) IMemory[i] = 0;
      for (i = 0; i <= 1023; i = i + 1) DMemory[i] = 0;

      fd = $fopen("C:/Users/Natnael/Documents/GitHub/CSCI_4203_Spring_2017_Lab2_Public/regs.dat","r");
      i = 0; 
      while (!$feof(fd)) begin
        code = $fscanf(fd, "%b\n", str);
        Regs[i] = str;
        i = i + 1;
      end

      i = 0; 
      fd = $fopen("C:/Users/Natnael/Documents/GitHub/CSCI_4203_Spring_2017_Lab2_Public/dmem.dat","r");
      while (!$feof(fd)) begin
        code = $fscanf(fd, "%b\n", str);
        DMemory[i] = str;
        i = i + 1;
      end

      i = 0; 
      fd = $fopen("C:/Users/Natnael/Documents/GitHub/CSCI_4203_Spring_2017_Lab2_Public/imem.dat","r");
      while (!$feof(fd)) 
       begin
        code = $fscanf(fd, "%b\n", str);
        IMemory[i] = str;
        i = i + 1;
       end

      #396
      i = 0; 
      fd = $fopen("C:/Users/Natnael/Documents/GitHub/CSCI_4203_Spring_2017_Lab2_Public/mem_result.dat","w" ); //open memory result file
      while (i < 32)
       begin
        str = DMemory[i];  //dump the first 32 memory values
        $fwrite(fd, "%b\n", str);
        i = i + 1;
       end
      $fclose(fd);

      i = 0; 
      fd = $fopen("C:/Users/Natnael/Documents/GitHub/CSCI_4203_Spring_2017_Lab2_Public/regs_result.dat","w" ); //open register result file
      while(i < 32)
       begin
        str = Regs[i];  //dump the register values
        $fwrite(fd, "%b\n", str);
        i = i + 1;
       end
      $fclose(fd);
   end

   always @ (posedge clock) begin
    if (~stall) begin // the first three pipeline stages stall if there is a load hazard
      if (nottaken) // if branch is not taken flush IFIDIR and return to original PC address
	begin
	  // flush predicted instruction and roll back to old PC
          IFIDIR <= no_op;
	  // restore PC to before jump address + 4
          PC <= PC - ({{16{IFIDIR[15]}}, IFIDIR[15:0]} << 2);
        end
      else if ((IFIDIR[31:26] == JRT) && (Regs[IFIDIR[25:21]] == 0))
	begin
          // flush what was fetched if jump is confirmed
	  // we dont know the values of registers until jrt is decode stage.
          IFIDIR <= no_op;
	  // pc will point to instruction after jump address for next cycle
	  // sign extend hardware required decode stage
	  PC <= PC + 4 + ({{16{IFIDIR[15]}}, IFIDIR[15:0]} << 2);
	end 
      // extra port to read from instruction memory.
      // Since IFIDIR is not updated immediately in this simulation, we need to read imem
      // at location PC [current program counter] so we can predict next instruction.
      else if (IMemory[PC >> 2][31:26] == BEQ) // checking the instuction while in fetch stage
        begin
	  // Predict branch taken 
	  IFIDIR <= IMemory[PC >> 2];
	  // prediction with pc relative addressing
          PC <= PC + 4 + ({{16{IMemory[PC >> 2][15]}}, IMemory[PC >> 2][15:0]} << 2);
      	end
      else
        begin 
          //first instruction in the pipeline is being fetched normally
          $display("IFIDIR updated \n");
          IFIDIR <= IMemory[PC >> 2];
          PC <= PC + 4;
        end

      // second instruction is in register fetch
      IDEXA <= Regs[IFIDIR[25:21]]; 
      IDEXB <= Regs[IFIDIR[20:16]]; // get two registers
      IDEXIR <= IFIDIR;  //pass along IR

      // third instruction is doing address calculation or ALU operation
      if ((IDEXop == LW) | (IDEXop == SW))  // address calculation & copy B
           EXMEMALUOut <= Ain + {{16{IDEXIR[15]}}, IDEXIR[15:0]};
      else if (IDEXop == LWCAB)
	 begin
	   if (Regs[IDEXIR[20:16]] < Regs[IDEXIR[15:11]]) EXMEMALUOut <= 1;
	   else EXMEMALUOut <= 0;
	 end
      else if (IDEXop == JRT) 
	 begin
	   if (Ain == 0) EXMEMALUOut <= Ain + 1; // R[rs] + 1
	   else EXMEMALUOut <= Ain; // R[rs] = R[rs]; basically do nothing
	 end
      else if (IDEXop == ALUop) 
        //case for the various R-type instructions
        case (IDEXIR[5:0]) 
          32: EXMEMALUOut <= Ain + Bin;  //add operation
          37: EXMEMALUOut <= Ain | Bin;  //OR operation
	  36: EXMEMALUOut <= Ain & Bin;  //AND operation
          42: //SLT operation
	    begin
	      if (Ain < Bin) EXMEMALUOut <= 1;  
	      else EXMEMALUOut <= 0; 
	    end
	  29: // cmov operation
	    begin
	      // rd = Regs[shamt]
	      if (Ain < Bin) EXMEMALUOut <= Regs[IDEXIR[10:6]];
	      // do nothing when Ain >= Bin
	      else EXMEMALUOut <= Regs[IDEXIR[15:11]];
	    end
          default: ; //other R-type operations: subtract, SLT, etc.
        endcase
      // pass along the IR & B register
      EXMEMIR <= IDEXIR; 
      EXMEMB <= IDEXB; 
     end
    else 
      EXMEMIR <= no_op; //Freeze first three stages of pipeline; inject a nop into the EX output

      //Mem stage of pipeline
      if (EXMEMop == ALUop) MEMWBValue <= EXMEMALUOut; //pass along ALU result
      else if (EXMEMop == JRT) MEMWBValue <= EXMEMALUOut; 
      else if (EXMEMop == LW) MEMWBValue <= DMemory[EXMEMALUOut >> 2];
      else if (EXMEMop == SW) DMemory[EXMEMALUOut >> 2] <= EXMEMB; //store
      else if (EXMEMop == LWCAB) // load with bound check
	begin // check the zero out of alu
	  if (EXMEMALUOut == 1) MEMWBValue <= DMemory[Regs[EXMEMIR[20:16]] >> 2];
	  else MEMWBValue <= 0;
	end

      //the WB stage
      MEMWBIR <= EXMEMIR; //pass along IR
      if ((MEMWBop == ALUop) & (MEMWBrd != 0)) Regs[MEMWBrd] <= MEMWBValue; // ALU operation
      else if ((MEMWBop == LW)& (MEMWBIR[20:16] != 0)) Regs[MEMWBIR[20:16]] <= MEMWBValue;
      else if ((MEMWBop == LWCAB) & (MEMWBIR[25:21] != 0)) Regs[MEMWBIR[25:21]] <= MEMWBValue;  // load with bound check
      else if ((MEMWBop == JRT) & (MEMWBIR[25:21] != 0)) Regs[MEMWBIR[25:21]] <= MEMWBValue;  // R[rs] = R[rs] + 1
   end
endmodule
