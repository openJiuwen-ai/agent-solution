"""
凭证要素提取提示词生成器单元测试
"""
import pytest
import base64
from pathlib import Path
from unittest.mock import patch, MagicMock


class TestCredentialPromptGenerator:
    """测试 CredentialPromptGenerator 类"""

    def test_build_code_mapping_hint(self, sample_code_mapping):
        """测试要素编码映射提示构建"""
        from prompt_generator import CredentialPromptGenerator

        # 创建实例（不实际调用 API）
        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        hint = generator._build_code_mapping_hint(sample_code_mapping)

        # 验证包含关键内容
        assert "【重要 - 字段命名规范覆盖】" in hint
        assert "E01001(凭证编号)" in hint
        assert "E01002(开票日期)" in hint
        assert "E02001(金额)" in hint
        assert "要素编码映射清单" in hint

    def test_render_template(self, sample_prompt_template):
        """测试模板渲染"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=sample_prompt_template):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        # 测试有 field_names_hint 的情况
        result = generator._render_template("这是字段命名提示")
        assert "这是字段命名提示" in result
        assert "{{ field_names_hint }}" not in result

        # 测试无 field_names_hint 的情况
        result = generator._render_template("")
        assert "这是字段命名提示" not in result

    def test_strip_markdown_code_blocks(self):
        """测试 markdown 代码块清理"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        # 测试带 markdown 代码块的文本
        text = "```markdown\n这是内容\n```"
        assert generator._strip_markdown_code_blocks(text) == "这是内容"

        # 测试不带代码块的文本
        text = "这是普通文本"
        assert generator._strip_markdown_code_blocks(text) == "这是普通文本"

        # 测试带语言标识的代码块
        text = "```json\n{\"key\": \"value\"}\n```"
        assert generator._strip_markdown_code_blocks(text) == "{\"key\": \"value\"}"

    def test_get_image_base64_from_file(self, tmp_path):
        """测试从文件读取图片转 base64"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        # 创建临时图片文件
        test_image = tmp_path / "test.jpg"
        test_content = b"fake image content"
        test_image.write_bytes(test_content)

        result = generator._get_image_base64(str(test_image))
        expected = base64.b64encode(test_content).decode()
        assert result == expected

    def test_get_image_base64_from_base64(self):
        """测试直接传入 base64"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        # 纯 base64
        test_content = base64.b64encode(b"fake image").decode()
        result = generator._get_image_base64(test_content)
        assert result == test_content

        # 带 data:image 前缀
        data_url = f"data:image/jpeg;base64,{test_content}"
        result = generator._get_image_base64(data_url)
        assert result == test_content

    def test_get_image_base64_invalid_input(self):
        """测试无效输入"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        with pytest.raises(ValueError, match="无法识别输入类型"):
            generator._get_image_base64("not_a_valid_path_or_base64")

    def test_generate_no_images(self):
        """测试无图片输入"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        result = generator.generate(images=[])
        assert result["success"] is False
        assert "至少需要一张图片" in result["error"]

    def test_code_mapping_grouping(self):
        """测试编码按前缀分组"""
        from prompt_generator import CredentialPromptGenerator

        with patch.object(CredentialPromptGenerator, '_load_template', return_value=""):
            generator = CredentialPromptGenerator(
                api_key="test-key",
                api_url="https://test.api/v1",
                model="test-model"
            )

        mappings = [
            {"code": "E01001", "name": "编号"},
            {"code": "E01002", "name": "日期"},
            {"code": "E02001", "name": "金额"},
        ]

        hint = generator._build_code_mapping_hint(mappings)

        # 验证分组显示
        assert "- E01:" in hint
        assert "- E02:" in hint
        assert "E01001(编号)" in hint
        assert "E01002(日期)" in hint
        assert "E02001(金额)" in hint
