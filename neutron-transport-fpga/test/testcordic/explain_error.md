# Analisi Errore CORDIC in cordicstagec.vhd

## Il Problema

La costante `kcinv` in `configcordicc.vhd` ha il **nome corretto** ma il **valore sbagliato**:

```vhdl
-- Attuale (ERRATO):
constant kcinv : signed(...) := X"0001A592148CFB85"; -- = 1.646760 (che è K)
```

## Perché è Sbagliato

1. **Nome della costante**: `kcinv` significa "K inverse" = 1/K
2. **Valore atteso**: 1/K = 0.607253 = `0x00009B74EDA8435E` in Q16.48
3. **Valore attuale**: K = 1.646760 = `0x0001A592148CFB85` in Q16.48

## Come viene Usata

In `sincos.vhd` riga 42:
```vhdl
statein_sig <= (kcinv, (others => '0'), alphar); -- x = kcinv, y = 0, z = angle
```

Il commento dice "x = 1/K", quindi `kcinv` dovrebbe contenere 0.607.

## Spiegazione del Guadagno CORDIC

L'algoritmo CORDIC introduce un guadagno:
- K = ∏(i=0 to n-1) √(1 + 2^(-2i)) ≈ 1.646760

Per compensare:
- Partiamo da x = 1/K invece di x = 1
- Dopo n iterazioni: x_final = K * (1/K) * cos(α) = cos(α) ✓

## Cosa Succede Ora (SBAGLIATO)

1. Inizializziamo x = K (invece di 1/K)
2. CORDIC applica guadagno: x_final = K * K * cos(α) = K² * cos(α)
3. Risultato: valori moltiplicati per K² = 2.711819x ✓ (corrisponde ai test!)

## Soluzione

Modificare `configcordicc.vhd` riga 60:
```vhdl
constant kcinv : signed(m_blocksize * m_blocks - 1 downto 0) := X"00009B74EDA8435E"; -- 1/K = 0.607253
```

**Nota**: Il nome `kcinv` è corretto (K-inverse), ma contiene il valore di K invece di 1/K!
