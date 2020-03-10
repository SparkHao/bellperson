// FinalityLabs - 2019
// Arbitrary size prime-field arithmetic library (add, sub, mul, pow)

// Greater than or equal
bool FIELD_gte(FIELD a, FIELD b) {
  for(char i = FIELD_LIMBS - 1; i >= 0; i--){
    if(a.val[i] > b.val[i])
      return true;
    if(a.val[i] < b.val[i])
      return false;
  }
  return true;
}

// Equals
bool FIELD_eq(FIELD a, FIELD b) {
  for(uchar i = 0; i < FIELD_LIMBS; i++)
    if(a.val[i] != b.val[i])
      return false;
  return true;
}

// Modular subtraction
FIELD FIELD_sub(FIELD a, FIELD b) {
  FIELD res = FIELD_sub_(a, b);
  if(!FIELD_gte(a, b)) res = FIELD_add_(res, FIELD_P);
  return res;
}

// Modular addition
FIELD FIELD_add(FIELD a, FIELD b) {
  FIELD res = FIELD_add_(a, b);
  if(FIELD_gte(res, FIELD_P)) res = FIELD_sub_(res, FIELD_P);
  return res;
}

/*
 * Montgomery reduction
 * Takes the result of a long multiplication (Which has twice the size of a FIELD)
 * as input and reduces it to a FIELD.
 * Learn more:
 * https://en.wikipedia.org/wiki/Montgomery_modular_multiplication
 * https://alicebob.cryptoland.net/understanding-the-montgomery-reduction-algorithm/
 */
FIELD FIELD_reduce(limb *limbs) {
  FIELD carries;
  for(uchar i = 0; i < FIELD_LIMBS; i++) {
    limb u = FIELD_INV * limbs[i];
    limb carry = 0;
    for(uchar j = 0; j < FIELD_LIMBS; j++)
      limbs[i + j] = mac_with_carry(u, FIELD_P.val[j], limbs[i + j], &carry);
    carries.val[i] = carry;
  }

  // Divide by R (Or take the upper half of `limbs` array as the final result)
  FIELD result;
  for(uchar i = 0; i < FIELD_LIMBS; i++) result.val[i] = limbs[i+FIELD_LIMBS];

  return FIELD_add(result, carries);
}

// Modular multiplication
FIELD FIELD_mul(FIELD a, FIELD b) {
  // CIOS Montgomery multiplication, inspired from Tolga Acar's thesis:
  // https://www.microsoft.com/en-us/research/wp-content/uploads/1998/06/97Acar.pdf
  limb t[FIELD_LIMBS + 2] = {0};
  for(uchar i = 0; i < FIELD_LIMBS; i++) {
    limb carry = 0;
    for(uchar j = 0; j < FIELD_LIMBS; j++)
      t[j] = mac_with_carry(a.val[j], b.val[i], t[j], &carry);
    t[FIELD_LIMBS] = add_with_carry(t[FIELD_LIMBS], &carry);
    t[FIELD_LIMBS + 1] = carry;

    carry = 0;
    limb m = FIELD_INV * t[0];
    mac_with_carry(m, FIELD_P.val[0], t[0], &carry);
    for(uchar j = 1; j < FIELD_LIMBS; j++)
      t[j - 1] = mac_with_carry(m, FIELD_P.val[j], t[j], &carry);

    t[FIELD_LIMBS - 1] = add_with_carry(t[FIELD_LIMBS], &carry);
    t[FIELD_LIMBS] = t[FIELD_LIMBS + 1] + carry;
  }

  FIELD result;
  for(uchar i = 0; i < FIELD_LIMBS; i++) result.val[i] = t[i];

  if(FIELD_gte(result, FIELD_P)) result = FIELD_sub_(result, FIELD_P);

  return result;
}

// Squaring is a special case of multiplication which can be done ~1.5x faster.
// https://stackoverflow.com/a/16388571/1348497
FIELD FIELD_sqr(FIELD a) {

  // Long multiplication (Diagonal elements are skipped)
  limb res[FIELD_LIMBS * 2] = {0};
  for(uchar i = 0; i < FIELD_LIMBS - 1; i++) {
    limb carry = 0;
    for(uchar j = i + 1; j < FIELD_LIMBS; j++)
      res[i + j] = mac_with_carry(a.val[i], a.val[j], res[i + j], &carry);
    res[i + FIELD_LIMBS] = carry;
  }

  // Double the result
  res[FIELD_LIMBS * 2 - 1] = res[FIELD_LIMBS * 2 - 2] >> (LIMB_BITS - 1);
  for(uchar i = FIELD_LIMBS * 2 - 2; i > 1; i--)
    res[i] = (res[i] << 1) | (res[i - 1] >> (LIMB_BITS - 1));
  res[1] <<= 1;

  // Process diagonal elements
  limb carry = 0;
  for(uchar i = 0; i < FIELD_LIMBS; i++) {
    res[i * 2] = mac_with_carry(a.val[i], a.val[i], res[i * 2], &carry);
    res[i * 2 + 1] = add_with_carry(res[i * 2 + 1], &carry);
  }

  return FIELD_reduce(res);
}

// Left-shift the limbs by one bit and subtract by modulus in case of overflow.
// Faster version of FIELD_add(a, a)
FIELD FIELD_double(FIELD a) {
  for(uchar i = FIELD_LIMBS - 1; i >= 1; i--)
    a.val[i] = (a.val[i] << 1) | (a.val[i - 1] >> (LIMB_BITS - 1));
  a.val[0] <<= 1;
  if(FIELD_gte(a, FIELD_P)) a = FIELD_sub_(a, FIELD_P);
  return a;
}

// Modular exponentiation (Exponentiation by Squaring)
// https://en.wikipedia.org/wiki/Exponentiation_by_squaring
FIELD FIELD_pow(FIELD base, uint exponent) {
  FIELD res = FIELD_ONE;
  while(exponent > 0) {
    if (exponent & 1)
      res = FIELD_mul(res, base);
    exponent = exponent >> 1;
    base = FIELD_sqr(base);
  }
  return res;
}


// Store squares of the base in a lookup table for faster evaluation.
FIELD FIELD_pow_lookup(__global FIELD *bases, uint exponent) {
  FIELD res = FIELD_ONE;
  uint i = 0;
  while(exponent > 0) {
    if (exponent & 1)
      res = FIELD_mul(res, bases[i]);
    exponent = exponent >> 1;
    i++;
  }
  return res;
}
