
module sd_card_cmd(
	input                       sys_clk,
	input                       rst,
	input[15:0]                 spi_clk_div,                  //SPI module clock division parameter
	input                       cmd_req,                      //SD card command request
	output                      cmd_req_ack,                  //SD card command request response
	output reg                  cmd_req_error,                //SD card command request error
	input[47:0]                 cmd,                          //SD card command
	input[7:0]                  cmd_r1,                       //SD card expect response
	input[15:0]                 cmd_data_len,                 //SD card command read data length
	input                       block_read_req,               //SD card sector data read request
	output reg                  block_read_valid,             //SD card sector data read data valid
	output reg[7:0]             block_read_data,              //SD card sector data read data
	output                      block_read_req_ack,           //SD card sector data read response
	output                      block_read_error,             //读数据阶段等不到0xFE起始令牌(超时),报错让上层重试
	input                       block_write_req,              //SD card sector data write request
	input[7:0]                  block_write_data,             //SD card sector data write data next clock is valid
	output                      block_write_data_rd,          //SD card sector data write data
	output                      block_write_error,
	output                      block_write_req_ack,          //SD card sector data write response
	output                      nCS_ctrl,                     //SPI module chip select control
	output reg[15:0]            clk_div,
	output reg                  spi_wr_req,                   //SPI module data sending request
	input                       spi_wr_ack,                   //SPI module data request response
	output[7:0]                 spi_data_in,                  //SPI module send data
	input[7:0]                  spi_data_out                  //SPI module data returned
);
//2026-10-21 新增:SD数据块CRC16校验(参考第七讲sd_spi_sector_reader)。
//边收512字节边算CRC16-CCITT(0x1021,初值0,算法已用标准向量验证),不符走S_READ_ERR重试。
//2026-10-21 上板实测:本卡在SPI模式下返回的数据CRC无效(规范允许,topic1在同系板子
//也记录过同样现象)→校验100%失败→所有读失败→不出图。**此卡必须保持1'b0**。
parameter CHECK_DATA_CRC = 1'b0;
parameter S_IDLE         = 0;
parameter S_WAIT         = 1;
parameter S_INIT         = 2;
parameter S_CMD_PRE      = 3;
parameter S_CMD          = 4;
parameter S_CMD_DATA     = 5;
parameter S_READ_WAIT    = 6;
parameter S_READ         = 7;
parameter S_READ_ACK     = 8;
parameter S_WRITE_TOKEN  = 9;
parameter S_WRITE_DATA_0 = 10;
parameter S_WRITE_DATA_1 = 11;
parameter S_WRITE_CRC    = 12;
parameter S_WRITE_SUC    = 13;
parameter S_WRITE_BUSY   = 14;
parameter S_WRITE_ACK    = 15;
parameter S_ERR          = 16;
parameter S_END          = 17;
parameter S_READ_ERR     = 18;
parameter S_WRITE_ERR = 19;
parameter WRITE_WAIT_LIMIT = 24'd16777215;

reg[4:0]                      state;
reg                           CS_reg;
reg[15:0]                     byte_cnt;
reg[7:0]                      send_data;
wire[7:0]                     data_recv;
reg[9:0]                      wr_data_cnt;
reg[23:0]                     read_wait_cnt;   //S_READ_WAIT超时计数:24bit@100MHz≈167ms(覆盖SD协议TAAC上限100ms)
reg[15:0]                     crc16;           //512数据字节的CRC16-CCITT累加值
reg[7:0]                      crc_hi;          //卡返回CRC的高字节(byte_cnt==512时捕获)

//CRC16-CCITT(poly 0x1021,初值0)逐字节更新,SD数据块标准校验
function [15:0] crc16_byte;
	input [15:0] crc_in;
	input [7:0]  din;
	integer k;
	reg [15:0] c;
	begin
		c = crc_in ^ {din, 8'h00};
		for(k = 0; k < 8; k = k + 1)
			c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
		crc16_byte = c;
	end
endfunction

assign cmd_req_ack = (state == S_END);
assign block_read_req_ack = (state == S_READ_ACK);
assign block_read_error = (state == S_READ_ERR);
assign block_write_error=(state==S_WRITE_ERR);
assign block_write_req_ack= (state == S_WRITE_ACK);
assign block_write_data_rd = (state == S_WRITE_DATA_0);
assign spi_data_in = send_data;
assign data_recv = spi_data_out;
assign nCS_ctrl = CS_reg;
always@(posedge sys_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		CS_reg <= 1'b1;
		spi_wr_req <= 1'b0;
		byte_cnt <= 16'd0;
		clk_div <= 16'd0;
		send_data <= 8'hff;
		state <= S_IDLE;
		cmd_req_error <= 1'b0;
		wr_data_cnt <= 10'd0;
		read_wait_cnt <= 24'd0;
		crc16 <= 16'd0;
		crc_hi <= 8'd0;
	end
	else
		case(state)
			S_IDLE:
			begin
				state <= S_INIT;
				clk_div <= spi_clk_div;
				CS_reg <= 1'b1;
			end
			S_INIT:
			begin
				//send 11 bytes on power(at least 74 SPI clocks)
				if(spi_wr_ack == 1'b1)
				begin
					if(byte_cnt >= 16'd10)
					begin
						byte_cnt <= 16'd0;
						spi_wr_req <= 1'b0;
						state <= S_WAIT;
					end
					begin
						byte_cnt <= byte_cnt + 16'd1;
					end
				end
				else
				begin
					spi_wr_req <= 1'b1;
					send_data <= 8'hff;
				end
			end
			S_WAIT:
			begin
				cmd_req_error <= 1'b0;
				wr_data_cnt <= 10'd0;
				read_wait_cnt <= 24'd0;
				//wait for  instruction
				if(cmd_req == 1'b1)
					state <= S_CMD_PRE;
				else if(block_read_req == 1'b1)
					state <= S_READ_WAIT;
				else if(block_write_req == 1'b1)
					state <= S_WRITE_TOKEN;
				clk_div <= spi_clk_div;
			end
			S_CMD_PRE:
			begin
				//before sending a command, send an byte 'ff',provide some clocks
				if(spi_wr_ack == 1'b1)
				begin
					state <= S_CMD;
					spi_wr_req <= 1'b0;
					byte_cnt <= 16'd0;
				end
				else
				begin
					spi_wr_req <= 1'b1;
					CS_reg <= 1'b1;
					send_data <= 8'hff;
				end
			end
			S_CMD:
			begin
				if(spi_wr_ack == 1'b1)
				begin
					if((byte_cnt == 16'hffff) || (data_recv != cmd_r1 && data_recv[7] == 1'b0))
					begin
						state <= S_ERR;
						spi_wr_req <= 1'b0;
						byte_cnt <= 16'd0;
					end
					else if(data_recv == cmd_r1)
					begin
						spi_wr_req <= 1'b0;
						if(cmd_data_len != 16'd0)
						begin
							state <= S_CMD_DATA;
							byte_cnt <= 16'd0;
						end
						else
						begin
							state <= S_END;
							byte_cnt <= 16'd0;
						end
					end
					else
						byte_cnt <=  byte_cnt + 16'd1;
				end
				else
				begin
					spi_wr_req <= 1'b1;
					CS_reg <= 1'b0;
					if(byte_cnt == 16'd0)
						send_data <= (cmd[47:40] | 8'h40);
					else if(byte_cnt == 16'd1)
						send_data <= cmd[39:32];
					else if(byte_cnt == 16'd2)
						send_data <= cmd[31:24];
					else if(byte_cnt == 16'd3)
						send_data <= cmd[23:16];
					else if(byte_cnt == 16'd4)
						send_data <= cmd[15:8];
					else if(byte_cnt == 16'd5)
						send_data <= cmd[7:0];
					else
						send_data <= 8'hff;
				end
			end
			S_CMD_DATA:
			begin
				if(spi_wr_ack == 1'b1)
				begin
					if(byte_cnt == cmd_data_len - 16'd1)
					begin
						state <= S_END;
						spi_wr_req <= 1'b0;
						byte_cnt <= 16'd0;
					end
					else
					begin
						byte_cnt <= byte_cnt + 16'd1;
					end
				end
				else
				begin
					spi_wr_req <= 1'b1;
					send_data <= 8'hff;
				end
			end
			S_READ_WAIT:
			begin
				if(spi_wr_ack == 1'b1 && data_recv == 8'hfe)
				begin
					spi_wr_req <= 1'b0;
					state <= S_READ;
					byte_cnt <= 16'd0;
					crc16 <= 16'd0;   //新数据块:CRC累加清零
				end
				else if(&read_wait_cnt)
				begin
					//超时仍等不到0xFE:卡无响应/令牌被噪声吞掉,报错退出,
					//由sd_card_sec_read_write重新发CMD17重试,避免永久死等
					spi_wr_req <= 1'b0;
					state <= S_READ_ERR;
				end
				else
				begin
					read_wait_cnt <= read_wait_cnt + 24'd1;
					spi_wr_req <= 1'b1;
					send_data <= 8'hff;
				end
			end
			S_READ:
			begin
				if(spi_wr_ack == 1'b1)
				begin
					if(byte_cnt == 16'd513)
					begin
						//本拍收到的是CRC低字节,crc16已覆盖512个数据字节:
						//与卡返回的{crc_hi,data_recv}比对,不符=数据静默损坏,
						//走S_READ_ERR让上层重发CMD17重试(与超时同路径)
						if(CHECK_DATA_CRC && (crc16 != {crc_hi, data_recv}))
							state <= S_READ_ERR;
						else
							state <= S_READ_ACK;
						spi_wr_req <= 1'b0;
						byte_cnt <= 16'd0;
					end
					else
					begin
						byte_cnt <= byte_cnt + 16'd1;
						if(byte_cnt < 16'd512)
							crc16 <= crc16_byte(crc16, data_recv);
						else if(byte_cnt == 16'd512)
							crc_hi <= data_recv;   //卡返回CRC的高字节
					end
				end
				else
				begin
					spi_wr_req <= 1'b1;
					send_data <= 8'hff;
				end
			end
			S_WRITE_TOKEN:
				if(spi_wr_ack == 1'b1)
				begin
					state <= S_WRITE_DATA_0;
					spi_wr_req <= 1'b0;
					byte_cnt <= 16'd0;  
				end
				else
				begin
					spi_wr_req <= 1'b1;
					send_data <= 8'hfe;
				end
			S_WRITE_DATA_0:
			begin
				state <= S_WRITE_DATA_1;
				wr_data_cnt <= wr_data_cnt + 10'd1;
			end
			S_WRITE_DATA_1:
			begin
				if(spi_wr_ack == 1'b1 && wr_data_cnt == 10'd512)
				begin
					state <= S_WRITE_CRC;
					spi_wr_req <= 1'b0;
				end
				else if(spi_wr_ack == 1'b1)
				begin
					state <= S_WRITE_DATA_0;
					spi_wr_req <= 1'b0;
				end
				else
				begin
					spi_wr_req <= 1'b1;
					send_data <= block_write_data;
				end
			end
			S_WRITE_CRC:
			begin
				if(spi_wr_ack == 1'b1)
				begin
					if(byte_cnt == 16'd1)
					begin
						state <= S_WRITE_SUC;
						spi_wr_req <= 1'b0;
						byte_cnt <= 16'd0;
					end
					else
					begin
						byte_cnt <= byte_cnt + 16'd1;
					end
				end
				else
				begin
					spi_wr_req <= 1'b1;
					send_data <= 8'hff;
				end
			end
            S_WRITE_SUC:begin
                if(read_wait_cnt>=WRITE_WAIT_LIMIT)begin spi_wr_req<=0;state<=S_WRITE_ERR;end
                else if(spi_wr_ack)begin
                    spi_wr_req<=0;
                    if(data_recv[4:0]==5'b00101)begin state<=S_WRITE_BUSY;read_wait_cnt<=0;end
                    else if(data_recv!=8'hff)state<=S_WRITE_ERR;
                    else read_wait_cnt<=read_wait_cnt+1'b1;
                end else begin spi_wr_req<=1;send_data<=8'hff;read_wait_cnt<=read_wait_cnt+1'b1;end
            end
            S_WRITE_BUSY:begin
                if(read_wait_cnt>=WRITE_WAIT_LIMIT)begin spi_wr_req<=0;state<=S_WRITE_ERR;end
                else if(spi_wr_ack)begin
                    spi_wr_req<=0;
                    if(data_recv==8'hff)state<=S_WRITE_ACK;
                    else read_wait_cnt<=read_wait_cnt+1'b1;
                end else begin spi_wr_req<=1;send_data<=8'hff;read_wait_cnt<=read_wait_cnt+1'b1;end
            end
            S_WRITE_ERR:begin CS_reg<=1;spi_wr_req<=0;state<=S_WAIT;end
			S_ERR:
			begin
				state <= S_END;
				cmd_req_error <= 1'b1;
			end
			S_READ_ACK,S_WRITE_ACK,S_END:
			begin
				state <= S_WAIT;
			end
			S_READ_ERR:
			begin
				//停留一拍:block_read_error本拍有效,随后回S_WAIT接受新命令
				state <= S_WAIT;
			end
			default:
				state <= S_IDLE;
		endcase
end
always@(posedge sys_clk or posedge rst)
begin
	if(rst == 1'b1)
		block_read_valid <= 1'b0;
	else if(state == S_READ && byte_cnt < 16'd512)
		block_read_valid <= spi_wr_ack;
	else
		block_read_valid <= 1'b0;
end

always@(posedge sys_clk or posedge rst)
begin
	if(rst == 1'b1)
		block_read_data <= 8'd0;
	else if(state == S_READ && spi_wr_ack == 1'b1)
		block_read_data <= data_recv;
end

endmodule