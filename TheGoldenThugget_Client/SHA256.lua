-- The Golden Thugget: pure-Lua SHA-256 (uses the client's 32-bit `bit` library)
-- Used for commit-reveal so rolls are fair without players being near each other.
local _, ns = ...
if ns.skip then return end

local bit = bit
local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift
local floor, format, byte, char, rep = math.floor, string.format, string.byte, string.char, string.rep

local MOD = 4294967296
local function u(x) return x % MOD end                        -- to unsigned 32
local function s(x) x = x % MOD; if x >= 2147483648 then return x - MOD end return x end -- to signed 32

local function AND(a, b) return u(band(s(a), s(b))) end
local function XOR(a, b) return u(bxor(s(a), s(b))) end
local function NOT(a) return u(bnot(s(a))) end
local function SHR(a, n) return u(rshift(s(a), n)) end
local function ROR(a, n) a = s(a); return u(bor(rshift(a, n), lshift(a, 32 - n))) end

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function preprocess(msg)
	local len = #msg
	local bits = len * 8
	local padLen = (55 - len) % 64
	local hi = floor(bits / MOD)
	local lo = bits % MOD
	local tail = char(
		floor(hi / 16777216) % 256, floor(hi / 65536) % 256, floor(hi / 256) % 256, hi % 256,
		floor(lo / 16777216) % 256, floor(lo / 65536) % 256, floor(lo / 256) % 256, lo % 256)
	return msg .. "\128" .. rep("\0", padLen) .. tail
end

local function sha256(msg)
	msg = preprocess(msg)
	local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	local w = {}
	for chunk = 1, #msg, 64 do
		for i = 0, 15 do
			local p = chunk + i * 4
			local b1, b2, b3, b4 = byte(msg, p, p + 3)
			w[i] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
		end
		for i = 16, 63 do
			local v15, v2 = w[i - 15], w[i - 2]
			local s0 = XOR(XOR(ROR(v15, 7), ROR(v15, 18)), SHR(v15, 3))
			local s1 = XOR(XOR(ROR(v2, 17), ROR(v2, 19)), SHR(v2, 10))
			w[i] = u(w[i - 16] + s0 + w[i - 7] + s1)
		end
		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for i = 0, 63 do
			local S1 = XOR(XOR(ROR(e, 6), ROR(e, 11)), ROR(e, 25))
			local ch = XOR(AND(e, f), AND(NOT(e), g))
			local t1 = u(h + S1 + ch + K[i + 1] + w[i])
			local S0 = XOR(XOR(ROR(a, 2), ROR(a, 13)), ROR(a, 22))
			local maj = XOR(XOR(AND(a, b), AND(a, c)), AND(b, c))
			local t2 = u(S0 + maj)
			h, g, f, e, d, c, b, a = g, f, e, u(d + t1), c, b, a, u(t1 + t2)
		end
		H[1], H[2], H[3], H[4] = u(H[1] + a), u(H[2] + b), u(H[3] + c), u(H[4] + d)
		H[5], H[6], H[7], H[8] = u(H[5] + e), u(H[6] + f), u(H[7] + g), u(H[8] + h)
	end
	local out = {}
	for i = 1, 8 do out[i] = format("%04x%04x", floor(H[i] / 65536), H[i] % 65536) end
	return table.concat(out)
end

ns.SHA256 = sha256
