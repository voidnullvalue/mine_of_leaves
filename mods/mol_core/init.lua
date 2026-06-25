mol = mol or {}

dofile(minetest.get_modpath("mol_core") .. "/util.lua")

-- Luanti 5.10 PseudoRandom returns 0..32767 internally, so keep
-- PseudoRandom:next(min, max) ranges within max - min <= 32767.
-- Derive separate seeds instead of requesting larger ranges.
function mol.new_prng(seed)
	return PseudoRandom(seed)
end
