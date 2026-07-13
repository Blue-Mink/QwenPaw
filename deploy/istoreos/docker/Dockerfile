# QwenPaw Docker 镜像构建文件
# 基于 python:3.10-slim，通过阿里云 PyPI 源安装 QwenPaw
# 使用方式: docker build -t qwenpaw:1.1.12 .

FROM python:3.10-slim

# 安装系统依赖
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        curl ca-certificates locales && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 配置中文字符集（可选）
RUN locale-gen zh_CN.UTF-8 2>/dev/null || true
ENV LANG zh_CN.UTF-8
ENV LC_ALL zh_CN.UTF-8

# 通过阿里云 PyPI 镜像源安装 QwenPaw
RUN pip install --no-cache-dir -i https://mirrors.aliyun.com/pypi/simple/ \
    qwenpaw==1.1.12.post3

# 安装 cloudpaw 插件依赖（可选，推荐）
RUN pip install --no-cache-dir -i https://mirrors.aliyun.com/pypi/simple/ \
    iac-code

# 验证安装
RUN qwenpaw --version

# 数据卷
VOLUME /root/.qwenpaw

# 默认端口
EXPOSE 19093

# 默认启动命令
ENTRYPOINT ["qwenpaw"]
CMD ["app", "--host", "0.0.0.0", "--port", "19093", "--log-level", "info"]
