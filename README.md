## NJUse软件测试课程作业（模糊测试方向）

> 在原项目基础上添加了更多比较Tricky的构建脚本，现在可以一键构建所有目标程序并生成初始种子😋。使用方法：进入`sh`目录，运行`chmod +x build_all.sh && ./build_all.sh`即可，结果位于根目录下的`output`文件夹中。

南京大学软件学院，2024秋季软件测试课程，模糊测试方向代码大作业选题指定的模糊目标程序。
选择该课题的小组应当在了解[AFL++](https://github.com/AFLplusplus/AFLplusplus)运行原理的基础上，参考AFL++的实现，使用Java或者Python语言自行实现模糊器。

### 1 项目结构

本项目目前包括以下内容：

- `fig/`: 统计图表示例，供参考。
- `sh/`: 一些比较Tricky的构建脚本，供参考。
- `*.tar.gz`: 项目压缩包。

### 2 常见指令

这里列举一些使用afl-cc插装C/C++项目时的常见指令。

```shell
# 安装常见依赖
apt-get install -y libtool build-essential cmake python3 gcc clang llvm file binutils

# 指定C/C++编译器。
export CC=<path-to-aflpp>/afl-cc
export CXX=<path-to-aflpp>/afl-cc

# 使用Autotools构建系统编译项目的典型流程。
./autogen.sh
./configure --disable-shared
make

# 使用cmake生成Makefile，之后编译项目。
cmake -S <path-to-src> -B <path-to-build> -G "Unix Makefiles"
cd <path-to-build>
make
```


### 3 模糊目标详细信息

下表为模糊目标/被测程序信息，从左到右每一列分别为目标ID、目标名称、目标所在项目压缩包、使用afl/afl++运行该目标时`--`部分后面的命令行内容，以及供参考的初始种子来源。

**注**：构建`lua`时注意阅读`src/Makefile`。

| TID  | Target  | Project  | AFL-CMD  |  Initial Seeds  |
|--------|--------|--------|--------| --------|
| T01 | `cxxfilt` | `binutils-2.28.tar.gz` | `cxxfilt` | `"_Z1fv"`, (LLM-Generate) |
| T02 | `readelf` | `binutils-2.28.tar.gz` |`readelf -a @@ @@` | `afl++/testcases/others/elf/` |
| T03 | `nm-new` | `binutils-2.28.tar.gz` | `nm-new @@` | `afl++/testcases/others/elf/` |
| T04 | `objdump` | `binutils-2.28.tar.gz` | `objdump -d @@` | `afl++/testcases/others/elf/` |
| T05 | `djpeg` | `libjpeg-turbo-3.0.4.tar.gz` | `djpeg @@` | `afl++/testcases/images/jpeg`, `<project>/testimages/` |
| T06 | `readpng` | `libpng-1.6.29.tar.gz` | `readpng` | `afl++/testcases/images/png/`, `<project>/tests/` |
| T07 | `xmllint` | `libxml2-2.13.4.tar.gz` | `xmllint @@` | `afl++/testcases/others/xml/`, `<project>/test/` |
| T08 | `lua` | `lua-5.4.7.tar.gz` | `lua @@` | https://github.com/lua/lua/tree/master/testes |
| T09 | `mjs` | `mjs-2.20.0.tar.gz` | `mjs -f @@` | `afl++/testcases/others/mjs/`, `<project>/tests/` |
| T10 | `tcpdump` | `tcpdump-tcpdump-4.99.5.tar.gz` | `tcpdump -nr @@` | `afl++/testcases/others/pcap/`, `<project>/tests/` |
