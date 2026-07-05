# 1 vLLM推理引擎
## 1.1 启动容器
先通过*docker images | grep vllm*命令找到vLLM的镜像id，如下：
```shell
xxx@a800-011:~$ docker images | grep vllm
m.daocloud.io/quay.io/ascend/vllm-ascend                            v0.13.0                                              36aaedd3fcc8   4 weeks ago     15.5GB
verl_vllm_ascend                                                    v0.9.1-dev-20250830                                  25c7d8229cb9   6 months ago    34.6GB
```
然后采用该容器id*36aaedd3fcc8*来启动容器，启动命令如下：
```shell
#!/bin/bash
IMAGES_ID=$1
NAME=$2
if [ $# -ne 2 ]; then
   echo "error: need one argument describing your container name."
   exit 1
fi
docker run --name ${NAME} -it -d --net=host --shm-size=500g \
     --privileged=true \
     -w /home \
     --device=/dev/davinci_manager \
     --device=/dev/hisi_hdc \
     --device=/dev/devmm_svm \
     --entrypoint=bash \
     -v /usr/local/dcmi:/usr/local/dcmi \
     -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
     -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
     -v /etc/ascend_install.info:/etc/ascend_install.info \
     -v /usr/local/sbin:/usr/local/sbin \
     -v /usr/bin/git:/usr/bin/git \
     -v /tmp:/tmp \
     -v /mnt/nas:/mnt/nas \
     -v /usr/share/zoneinfo/Asia/Shanghai:/etc/localtime \
     ${IMAGES_ID}
```
将该脚本命名为run_vllm.sh，然后通过命令*bash ./run_vllm.sh 36aaedd3fcc8 容器名称*来启动容器。
> 注意：这里的id是上一步查询到的镜像id，容器名称可以自定义。

如果没有指定版本的vLLM，可以访问[quay.io](https://quay.io/repository/ascend/vllm-ascend?tab=tags)，然后选择需要的版本进行下载，下载命令：*docker pull quay.io/ascend/vllm-ascend:v0.13.0*。由于这个镜像非常大，下载需要花费很长时间，建议通过国内镜像源的方式下载，如：*docker pull m.daocloud.io/quay.io/ascend/vllm-ascend:v0.13.0*。
## 1.2 启动推理服务
先下载好模型权重文件，然后根据环境提供的卡信息，设置相关的推理服务启动脚本
```shell
#!/bin/sh
# 指定卡信息，这里采用双卡
export ASCEND_RT_VISIBLE_DEVICES=2,3
# Set the operator dispatch pipeline level to 1 and disable manual memory control in ACLGraph
export TASK_QUEUE_ENABLE=1
# jemalloc
export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD
# Enable the AIVector core to directly schedule ROCE communication
export HCCL_OP_EXPANSION_MODE="AIV"
# enable dense model
export VLLM_ASCEND_ENABLE_DENSE_OPTIMIZE=1
# 使能FlashComm_v1优化器，前提是多卡，单卡需要注释掉.
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1
# enable prefetch
export VLLM_ASCEND_ENABLE_PREFETCH_MLP=1
# 模型路径
export MODEL_PATH="<your-model-path>"

vllm serve ${MODEL_PATH} \
          --host 0.0.0.0 \
          --port 8081 \
          --served-model-name qwen3-8b \
          --trust-remote-code \
          --async-scheduling \
          --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY", "cudagraph_capture_sizes":[1,2,4,8,12,16]}' \
          --max-num-seqs 16 \
          --gpu-memory-utilization 0.9 \
          --max-model-len 4096 \
          -tp 2 \
          --max-num-batched-tokens 65536 \
          --reasoning-parser qwen3 \
          --default-chat-template-kwargs '{"enable_thinking": false}'
```
保存为sh文件，然后通过bash命令来启动。

## 1.3 性能测试
先下载ais_bench测试工具，并安装好了相关依赖,命令如：
```shell
git clone https://gitee.com/aisbench/benchmark.git
cd benchmark/
pip3 install -e ./ --use-pep517
```
性能测试可以使用官方的[开源数据集](https://ais-bench-benchmark.readthedocs.io/zh-cn/latest/base_tutorials/all_params/datasets.html#id3)，也可以使用自定义的数据集（注意采用jsonl格式，每行是一个字典，关键字必须包含question和answer）,执行命令如下：
```shell
ais_bench --models vllm_api_general_chat --datasets gsm8k_gen -m perf
ais_bench --models vllm_api_general_chat --custom-dataset-path 自定义数据集jsonl文件路径 -m perf
```
在测试执行，需要先对*vllm_api_general_chat*的参数完成修改,主要修改 path、model、host_ip、host_port、max_out_len（最大输出长度）、batch_size（并发数）：
```python
from ais_bench.benchmark.models import VLLMCustomAPIChat
from ais_bench.benchmark.utils.postprocess.model_postprocessors import extract_non_reasoning_content

models = [
    dict(
        attr="service",
        type=VLLMCustomAPIChat,
        abbr="vllm-api-general-chat",
        path="<your-model-path>",
        model="qwen3-8b",
        stream=False,
        request_rate=0,
        use_timestamp=False,
        retry=2,
        api_key="",
        host_ip="127.0.0.1",
        host_port=8081,
        url="",
        max_out_len=12,
        batch_size=10,
        trust_remote_code=False,
        generation_kwargs=dict(
            temperature=0.1,
            ignore_eos=False,
        ),
        pred_postprocessor=dict(type=extract_non_reasoning_content),
    )
]
```
测试完毕后，将会显示具体的测试结果，如TTFT（首token）、TPOP（增量token）、Throughput（吞吐量）等数据。从性能测试对比上看，`OutputTokens`对TTFT影响很大，对于首token性能要求较高的场景，需要尽量减少输出长度。

## 1.4 关闭思考
当前很多模型部署后自动开启思考模式。在思考模式下，大模型输出内容自动包含`<think></think>`字段，这部分占用了输出token长度，也严重影响TTFT性能，从实际性能的指标出发考虑去掉思考模式。不同模型的处理不一样，这里以我实际操作的模型为例。
- Qwen3-8B

配置启动模型服务的参数包含*--default-chat-template-kwargs '{"enable_thinking": false}'*，就可以去掉思考模式。这样带来的后果是无法强制开启思考了。
- Qwen3-30B

Qwen3-30B包含了思考（Qwen3-30B-A3B-Thinking-2507）和非思考（Qwen3-30B-A3B-Instruct-2507）2种模型，需要注意使用非思考模型权重。操作步骤同Qwen3-8B

- GLM4.7 flash

# 1.5 压力测试
## 1.5.1 使用vllm bench serve方式
随机数据压测，其中`num-prompts`参数控制压测多少轮，`max-concurrency`参数控制并发数，`prefix_repetition-prefix-len`表示输入的不变部分长度（类似系统提示词），`prefix_repetition-suffix-len`表示输入的可变部分长度（类似用户输入），`prefix_repetition-output-len`表示输出长度
```shell
vllm bench serve \
  --max-concurrency 10 \
  --num-prompts 1 \
  --host 127.0.0.1 \
  --port 8081 \
  --backend openai-chat \
  --model qwen3-8b \
  --dataset-name prefix_repetition \
  --prefix_repetition-prefix-len 3400 \
  --prefix_repetition-suffix-len 1024 \
  --prefix_repetition-output-len 12 \
  --prefix_repetition-num-prefixes 5 \
  --seed 1000 \
  --tokenizer <your-model-path> \
  --endpoint /v1/chat/completions \
  --ignore-eos
```

# 1.6 日志打印
在测试过程种，尤其是非知连的环境，可能存在输入被篡改的问题，需要在服务端开启日志定位
- 设置日志级别为debug
```shell
export VLLM_LOGGING_LEVEL=DEBUG
```
- 打印请求日志
```shell
--enable-log-requests
```
- 打印输出日志
```shell
--enable-log-output
```

