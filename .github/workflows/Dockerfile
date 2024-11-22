FROM ubuntu:22.04

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装基础依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    python3-dev \
    automake \
    cmake \
    git \
    flex \
    bison \
    libglib2.0-dev \
    libpixman-1-dev \
    python3-setuptools \
    cargo \
    libgtk-3-dev \
    lld \
    llvm \
    llvm-dev \
    clang \
    ninja-build \
    cpio \
    libcapstone-dev \
    wget \
    curl \
    python3-pip \
    libtool-bin \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 复制项目文件
COPY . .

# 执行构建脚本
CMD ["sh", "-c", "cd sh && bash build_all.sh && cp -r ../output/* /output/"]
