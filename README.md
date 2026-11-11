# AES-128 Encryption Accelerator

## 1. Project Overview
This project implements an AES-128 hardware accelerator for encrypting 128-bit plaintext using a 128-bit key.

## 2. Design Specifications
- **Algorithm:** AES-128 Encryption
- **Block Size:** 128 bits
- **Key Size:** 128 bits
- **Number of Rounds:** 10
- **Target Clock Frequency:** 200 MHz
- **Target Throughput:** At least 4.0 Gb/s
- **Technology:** 45nm ASIC PDK

## 3. AES Architecture
The encryption process consists of:
- Initial AddRoundKey
- 9 main rounds: SubBytes, ShiftRows, MixColumns, AddRoundKey
- Final round: SubBytes, ShiftRows, AddRoundKey

The design also includes AES-128 key expansion to generate 11 round keys.

## 4. Hardware Interface
| Signal | Description |
|---|---|
| `i_clk` | Clock input |
| `i_rst_n` | Active-low reset |
| `i_key_valid` | Key input valid |
| `o_key_ready` | Key input ready |
| `i_key` | 128-bit encryption key |
| `i_data_valid` | Plaintext input valid |
| `o_data_ready` | Plaintext input ready |
| `i_plaintext` | 128-bit plaintext |
| `o_cipher_valid` | Ciphertext output valid |
| `i_cipher_ready` | Ciphertext output ready |
| `o_ciphertext` | 128-bit ciphertext |

## 5. Design Flow
1. Architecture exploration
2. RTL design using SystemVerilog
3. Functional simulation and verification
4. Logic synthesis
5. Timing and throughput evaluation

## 6. Verification
The design will be verified using known AES test vectors, multiple plaintext blocks, different keys, reset conditions, and ready/valid handshakes.

**Reference Test Vector:**
- Plaintext: `00112233445566778899aabbccddeeff`
- Key: `000102030405060708090a0b0c0d0e0f`
- Expected Ciphertext: `69c4e0d86a7b0430d8cdb78070b4c55a`

## 7. Synthesis Results
| Metric | Result |
|---|---|
| Cell Area | TBD |
| Critical Path Delay | TBD |
| Maximum Frequency | TBD |
| Throughput | TBD |

## 8. Project Information
- **Course:** EE3213 – Digital System Design and Verification
- **Project:** Milestone 1 – AES-128 Encryption Accelerator
- **University:** Ho Chi Minh City University of Technology (HCMUT)
