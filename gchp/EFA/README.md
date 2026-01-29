# EFA tweaks for GCHP

> These tweaks are for running GCHP on ParallelCluster with multi-nodes with EFA enabled

Add the following snippets to GCHP launch script if applies:

To avoid hanging forever at diagnostic writing and checkpointing, see discussion in https://github.com/geoschem/GCHP/issues/493
```bash
sed -i -E \
  -e 's/^([[:space:]]*NUM_WRITERS:[[:space:]]*).*/\16/' \
  -e 's/^([[:space:]]*WRITE_RESTART_BY_OSERVER:[[:space:]]*).*/\1YES/' \
  GCHP.rc
```

```bash
# When using OpenMPI
export OMPI_MCA_btl=^ofi
export OMPI_MCA_btl_tcp_if_exclude="lo,docker0,virbr0"
export OMPI_MCA_btl_if_exclude="lo,docker0,virbr0"
```

To avoid crashing when core counts > 1000, see https://github.com/ofiwg/libfabric/issues/11329
```bash
export FI_EFA_ENABLE_SHM_TRANSFER=0
export OMPI_MCA_mtl_ofi_provider_exclude=shm
```
