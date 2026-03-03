# Verifica Formule CORDIC in cordicstagec.vhd

## Formule CORDIC Circolare (Modalità Rotazione)

Le formule corrette per il CORDIC circolare in modalità rotazione sono:

### Se z >= 0 (rotazione antioraria):
```
x' = x - y * 2^(-i)
y' = y + x * 2^(-i)  
z' = z - atan(2^(-i))
```

### Se z < 0 (rotazione oraria):
```
x' = x + y * 2^(-i)
y' = y - x * 2^(-i)
z' = z + atan(2^(-i))
```

## Implementazione in cordicstagec.vhd

### Righe 36-43 (z < 0):
```vhdl
stateout.x <= statein.x + shift_right(statein.y, iter);
stateout.y <= statein.y - shift_right(statein.x, iter);
stateout.z <= statein.z + alpha;
```
✓ CORRETTO

### Righe 45-51 (z >= 0):
```vhdl
stateout.x <= statein.x - shift_right(statein.y, iter);
stateout.y <= statein.y + shift_right(statein.x, iter);
stateout.z <= statein.z - alpha;
```
✓ CORRETTO

## Conclusione

Le formule in `cordicstagec.vhd` sono **corrette**. 

L'errore è definitivamente nella costante `kcinv` in `configcordicc.vhd`:
- Valore attuale: 1.646760 (che è K)
- Valore corretto: 0.607253 (che è 1/K)

Il fatto che i risultati siano 2.71x più grandi (K² = 2.71) conferma che stiamo inizializzando con K invece di 1/K.
