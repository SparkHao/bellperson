/*
 * FFT algorithm is inspired from: http://www.bealto.com/gpu-fft_group-1.html
 */
__kernel void GROUP_fft(__global GROUP* x, // Source buffer
                        __global GROUP* y, // Destination buffer
                        __global FIELD* pq, // Precalculated twiddle factors
                        __global FIELD* omegas, // [omega, omega^2, omega^4, ...]
                        __local GROUP* u, // Local buffer to store intermediary values
                        uint n, // Number of elements
                        uint lgp, // Log2 of `p` (Read more in the link above)
                        uint deg, // 1=>radix2, 2=>radix4, 3=>radix8, ...
                        uint max_deg) // Maximum degree supported, according to `pq` and `omegas`
{
  uint lid = get_local_id(0);
  uint lsize = get_local_size(0);
  uint index = get_group_id(0);
  uint t = n >> deg;
  uint p = 1 << lgp;
  uint k = index & (p - 1);

  x += index;
  y += ((index - k) << deg) + k;

  uint count = 1 << deg; // 2^deg
  uint counth = count >> 1; // Half of count

  uint counts = count / lsize * lid;
  uint counte = counts + count / lsize;

  // Compute powers of twiddle
  FIELD twiddle = FIELD_pow_lookup(omegas, (n >> lgp >> deg) * k);
  FIELD tmp = FIELD_pow(twiddle, counts);
  for(uint i = counts; i < counte; i++) {
    u[i] = GROUP_mul(x[i*t], tmp);
    tmp = FIELD_mul(tmp, twiddle);
  }
  barrier(CLK_LOCAL_MEM_FENCE);

  uint pqshift = max_deg - deg;
  for(uint rnd = 0; rnd < deg; rnd++) {
    uint bit = counth >> rnd;
    for(uint i = counts >> 1; i < counte >> 1; i++) {
      uint di = i & (bit - 1);
      uint i0 = (i << 1) - di;
      uint i1 = i0 + bit;
      GROUP tmp = u[i0];
      u[i0] = GROUP_add(u[i0], u[i1]);
      u[i1] = GROUP_sub(tmp, u[i1]);
      if(di != 0) u[i1] = GROUP_mul(u[i1], pq[di << rnd << pqshift]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);
  }

  for(uint i = counts >> 1; i < counte >> 1; i++) {
    y[i*p] = u[bitreverse(i, deg)];
    y[(i+counth)*p] = u[bitreverse(i + counth, deg)];
  }
}
