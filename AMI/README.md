# Building ParallelCluster AMI
See reference in https://docs.aws.amazon.com/parallelcluster/latest/ug/building-custom-ami-v3.html

# Steps to create a GCHP/WRFGC AMI
1. Follow the reference above and log onto an EC2 instance with a base ParallelCluster AMI like `aws-parallelcluster-3.13.0-amzn2023-hvm-x86_64-xxxx`. Note that the base AMI depends on your ParallelCluster version, operating system, hardware architecture. You can find the base AMI in Amazon Community AMIs.
2. Use `postinstall.sh` to install spack
```bash
wget https://raw.githubusercontent.com/spack/spack-configs/refs/heads/main/AWS/parallelcluster/postinstall.sh
sudo bash postinstall.sh --prefix /opt --no-intel-compiler --no-arm-compiler
```
track installation progress in `/var/log/spack-postinstall.log`
```bash
tail -f /var/log/spack-postinstall.log
```
3. Create `gchp_env` and `wrfgc_env`

The installation will take ~30 minutes
```bash
spack env create gchp_env
sudo mv gchp_env.yaml /opt/spack/var/spack/environments/gchp_env/spack.yaml
spack env activate gchp_env
spack concretize -f
spack install
```

```bash
spack env create wrfgc_env
sudo mv wrfgc_env.yaml /opt/spack/var/spack/environments/wrfgc_env/spack.yaml
spack env activate wrfgc_env
spack concretize -f
spack install
```
4. Prepare env file for WRFGC
```bash
sudo bash jasper_install.sh
sudo bash wrfgc_env_config.sh
```

# Usage

GCHP
```bash
spack env activate gchp_env
```

WRFGC
```bash
source /opt/geos-chem/env/wrfgc
```
