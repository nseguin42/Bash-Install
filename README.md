# Bash-Install
A somewhat flexible script for running code blocks with dependencies. By default, installs some packages from the AUR with `paru`:

    llvm-minimal-git llvm-libs-minimal-git
    lib32-llvm-minimal-git lib32-llvm-libs-minimal-git
    rocm-llvm rocm-opencl-runtime
 
It does so with the following logic:
* if llvm fails, build mesa anyway, and don't attempt to upgrade other versions of llvm. 
* if mesa fails, revert llvm afterwards so our mesa and llvm builds match; stop attempting to upgrade llvm/mesa.
* repeat with the lib32 and rocm versions.

The advantages of this approach:
* At the end, we have updated as much as possible,
* circumventing issues that paru has with mesa-git's makepkg by installing manually,
* making sure that our installed mesa version(s) match our installed llvm version(s), 
* and making it *reasonably* likely that our mesa versions match.

Each package is treated internally as a "module," which is an arbitrary code block. You can add, remove, and modules in a straightforward way. With some imagination, I'm sure there's another application!
