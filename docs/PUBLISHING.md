# GitHub 上传与发布说明

项目名称为 **WordLens**，目标仓库为 [hxixih/WordLens](https://github.com/hxixih/WordLens)。本文说明源码上传和后续版本发布流程。

## 哪些内容上传到仓库

| 内容 | 处理方式 | 用途 |
| --- | --- | --- |
| `Source/` | 提交到仓库 | 完整的原生应用源码与图标生成程序。 |
| `Tests/` | 提交到仓库 | 80 项核心测试和 38 项兼容性测试。 |
| `Info.plist` | 提交到仓库 | 应用版本、Bundle ID 和网络配置。 |
| `build.sh`、`test.sh`、`make_icns.py` | 提交到仓库 | 让其他开发者能够构建并验证应用。 |
| `package_release.sh` | 提交到仓库 | 生成供普通用户下载的应用压缩包。 |
| `README.md`、`LICENSE`、`CHANGELOG.md`、`CONTRIBUTING.md` | 提交到仓库 | 项目介绍、使用、授权、版本和贡献说明。 |
| `.gitignore`、`.github/` | 提交到仓库 | 忽略规则、自动构建测试和问题模板；注意保留隐藏文件。 |
| `docs/` | 提交到仓库 | 发布说明和项目自生成图标。 |
| 编译好的 `.app`、应用 ZIP 和校验文件 | 上传到 GitHub Releases | 普通用户的下载入口，不需要放进源码提交。 |
| `dist/`、`work/`、模块缓存、测试二进制 | 不提交 | 可由构建和测试脚本重新生成，已被忽略。 |
| `.DS_Store`、编辑器状态、运行日志 | 不提交 | 本机或临时文件，已被忽略。 |
| API Key、钥匙串、个人设置、私密文档 | 不提交 | 用户运行时数据不属于项目源码。 |

源码目录没有包含原参考截图、聊天附件、个人电脑路径、翻译历史或实际模型密钥。测试中的 `test-key` 是模拟字符串。

## 许可证与署名

当前整理采用 **MIT License**，版权署名为 `WordLens contributors`。发布前可以把许可证版权行改为你的姓名、GitHub 昵称或组织名称。许可证介绍可参考 [GitHub 的 MIT 说明](https://choosealicense.com/licenses/mit/)。

## 创建仓库并上传

仓库名称为 `WordLens`，描述可使用：

> 原生 macOS AI 划词翻译工具，支持网页、PDF 复制兼容模式和自定义 OpenAI 兼容接口。

1. 在 GitHub 新建 **Public** 仓库。由于目录已带 README、许可证和忽略文件，创建时可不自动生成这些文件。
2. 上传本目录中的内容，使 `README.md`、`Source/` 和 `build.sh` 位于仓库根目录。
3. 使用 Git 推送可以保留 `.github/` 和 `.gitignore` 等隐藏文件。若使用网页上传，请单独确认这些文件也已上传；网页上传不会替你应用本机 `.gitignore`。

使用 Git 的示例：

```bash
# 进入这个开源目录，再初始化和提交
git init -b main
git add .
git status
git commit -m "Initial open source release"

git remote add origin https://github.com/hxixih/WordLens.git
git push -u origin main
```

请在 `git status` 中确认源码、文档和 `.github/` 已加入，`dist/`、`work/` 和 `.app` 未加入。Git 提交需要你已配置自己的用户名和邮箱，并完成 GitHub 身份验证。

## 发布应用下载包

在项目目录执行：

```bash
bash build.sh
bash test.sh
bash package_release.sh
```

得到：

```text
dist/WordLens-v1.0.2-Intel.zip
dist/WordLens-v1.0.2-Intel.zip.sha256
```

在 GitHub 的 Releases 页面新建版本，使用标签 `v1.0.2`，标题可写 `WordLens 1.0.2 — Intel macOS`。上传上述 ZIP 和校验文件，发布说明可使用：

> 原生 macOS 划词翻译应用，支持自定义 AI 接口。此版本新增 PDF / 复制兼容模式、选区范围读取和延迟重试。下载包面向 Intel Mac，运行不需要额外的第三方运行时；首次使用需设置模型参数并授予辅助功能权限。默认采用本地临时签名，未经 Apple 公证。详见 README。

用户可以在 ZIP 同目录验证下载完整性：

```bash
shasum -a 256 -c WordLens-v1.0.2-Intel.zip.sha256
```

更新 README 中的“当前版本”、`Info.plist` 和 `CHANGELOG.md` 后，打包脚本会从 `Info.plist` 读取版本号生成新文件名。

## 自动构建测试

`.github/workflows/ci.yml` 会在主分支推送、Pull Request 或手动触发时运行构建、118 项模拟测试和签名检查。采用 GitHub 提供的 [`macos-15-intel` 执行环境](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)，与当前 Intel 构建目标对应。

工作流只有仓库读取权限，不需要添加模型 API Key，也不会自动创建 Release。每次上传后，查看 [Actions](https://github.com/hxixih/WordLens/actions) 页确认远程构建结果；本地测试结果不能代替远程 CI 状态。
