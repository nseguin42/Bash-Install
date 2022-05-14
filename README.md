# Bash-Install
A somewhat flexible script for running code blocks with dependencies. By default, installs some packages from the AUR with `paru`:

    llvm-minimal-git llvm-libs-minimal-git
    lib32-llvm-minimal-git lib32-llvm-libs-minimal-git
    rocm-llvm rocm-opencl-runtime
 
It does so with the following logic.

try to install llvm. if it fails:

* build mesa anyway. llvm is treated as a soft dependency of mesa.
* don't attempt to upgrade other versions of llvm. llvm is a dependency for the other versions of llvm.

try to install mesa. if it fails:

* revert llvm to the previous version, so our mesa and llvm builds match. llvm is a codependency of mesa, so if mesa fails, llvm should fail.
* since llvm was reverted, again we do not attempt to upgrade the other versions of llvm.
* attempt to update mesa again after reverting llvm. if mesa fails again, do not upgrade the other versions of mesa.

repeat with the lib32 and rocm versions.

The advantages of this approach:
* At the end, we have updated as much as possible,
* circumventing issues that paru has with mesa-git's makepkg by installing manually,
* making sure that our installed mesa version(s) match our installed llvm version(s), 
* and making it *reasonably* likely that our mesa versions match.

Each package is treated internally as a "module," which is an arbitrary code block. You can add, remove, and modules in a straightforward way. With some imagination, I'm sure there's another application!
