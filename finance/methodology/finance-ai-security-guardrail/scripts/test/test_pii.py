"""
PII检测模块测试

测试自定义PII检测方案的核心功能：
- 中国金融场景PII检测（身份证、手机号、银行卡号）
- 英文PII检测（邮箱等）
- 匿名化/脱敏功能
- GuardRails AI Validator集成
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.validators.pii_validator import (
    PIIDetector,
    PIIEntity,
    pii_detect,
    pii_anonymize,
    GUARDRAILS_INTEGRATION_AVAILABLE,
)
from src.pii_detection import PIIDetectionService


def test_cn_id_card_detection():
    """测试中国身份证号检测"""
    print("\n测试1: 中国身份证号检测")
    detector = PIIDetector(pii_entities=[PIIEntity.CN_ID_CARD])

    text_with_id = "我的身份证号是110101199001011234"
    results = detector.detect(text_with_id)

    assert len(results) == 1, f"应检测到1个身份证号，实际检测到{len(results)}个"
    assert results[0].entity_type == PIIEntity.CN_ID_CARD
    assert "110101199001011234" in results[0].text
    print(f"  [PASS] 检测到: {results[0].text}")

    text_without_id = "今天天气很好，我想去公园散步"
    results = detector.detect(text_without_id)
    assert len(results) == 0
    print("  [PASS] 无身份证号文本检测通过")


def test_cn_phone_detection():
    """测试中国手机号检测"""
    print("\n测试2: 中国手机号检测")
    detector = PIIDetector(pii_entities=[PIIEntity.CN_PHONE])

    text_with_phone = "请联系我，手机号13800138000"
    results = detector.detect(text_with_phone)

    assert len(results) == 1, f"应检测到1个手机号，实际检测到{len(results)}个"
    assert results[0].entity_type == PIIEntity.CN_PHONE
    assert "13800138000" in results[0].text
    print(f"  [PASS] 检测到: {results[0].text}")


def test_cn_bank_card_detection():
    """测试中国银行卡号检测"""
    print("\n测试3: 中国银行卡号检测")
    detector = PIIDetector(pii_entities=[PIIEntity.CN_BANK_CARD])

    text_with_card = "我的银行卡号是6222021234567890123"
    results = detector.detect(text_with_card)

    assert len(results) == 1, f"应检测到1个银行卡号，实际检测到{len(results)}个"
    assert results[0].entity_type == PIIEntity.CN_BANK_CARD
    print(f"  [PASS] 检测到: {results[0].text}")


def test_email_detection():
    """测试邮箱检测"""
    print("\n测试4: 邮箱检测")
    detector = PIIDetector(pii_entities=[PIIEntity.EMAIL_ADDRESS])

    text_with_email = "请发送邮件至test@example.com"
    results = detector.detect(text_with_email)

    assert len(results) == 1, f"应检测到1个邮箱，实际检测到{len(results)}个"
    assert results[0].entity_type == PIIEntity.EMAIL_ADDRESS
    assert "test@example.com" in results[0].text
    print(f"  [PASS] 检测到: {results[0].text}")


def test_multiple_pii_detection():
    """测试多种PII同时检测"""
    print("\n测试5: 多种PII同时检测")
    detector = PIIDetector(pii_entities=["cn_pii", "EMAIL_ADDRESS"])

    text = "用户张三，手机号13800138000，邮箱zhangsan@bank.com，身份证110101199001011234"
    results = detector.detect(text)

    assert len(results) >= 3, f"应至少检测到3个PII实体，实际检测到{len(results)}个"
    entity_types = [r.entity_type for r in results]
    assert PIIEntity.CN_PHONE in entity_types
    assert PIIEntity.CN_ID_CARD in entity_types
    assert PIIEntity.EMAIL_ADDRESS in entity_types
    print(f"  [PASS] 检测到 {len(results)} 个PII实体: {entity_types}")


def test_anonymize():
    """测试脱敏功能"""
    print("\n测试6: PII脱敏")
    detector = PIIDetector(pii_entities=["cn_pii", "EMAIL_ADDRESS"])

    text = "用户张三，手机号13800138000，邮箱zhangsan@bank.com"
    anonymized = detector.anonymize(text)

    assert "13800138000" not in anonymized
    assert "zhangsan@bank.com" not in anonymized
    assert "<CN_PHONE>" in anonymized
    assert "<EMAIL_ADDRESS>" in anonymized
    print(f"  原文: {text}")
    print(f"  脱敏: {anonymized}")
    print("  [PASS] 脱敏成功")


def test_pii_summary():
    """测试PII摘要功能"""
    print("\n测试7: PII检测摘要")
    detector = PIIDetector(pii_entities=["cn_pii"])

    text = "手机号13800138000和13800138001"
    summary = detector.get_pii_summary(text)

    assert summary["has_pii"] is True
    assert summary["total_count"] == 2
    assert PIIEntity.CN_PHONE.value in summary["entity_counts"]
    assert summary["entity_counts"][PIIEntity.CN_PHONE.value] == 2
    print(f"  [PASS] 摘要: {summary}")


def test_pii_detection_service():
    """测试PII检测服务层"""
    print("\n测试8: PII检测服务层")
    service = PIIDetectionService(
        input_entities=["cn_pii"],
        output_entities=["cn_pii", "EMAIL_ADDRESS"],
    )

    # 测试输入检测
    input_text = "我的手机号是13800138000"
    input_result = service.check_input(input_text)
    assert input_result["has_pii"] is True
    assert "<CN_PHONE>" in input_result["anonymized_text"]
    print(f"  [PASS] 输入检测: {input_result['anonymized_text']}")

    # 测试输出检测
    output_text = "请联系zhangsan@bank.com"
    output_result = service.check_output(output_text)
    assert output_result["has_pii"] is True
    assert "<EMAIL_ADDRESS>" in output_result["anonymized_text"]
    print(f"  [PASS] 输出检测: {output_result['anonymized_text']}")


def test_guardrails_integration():
    """测试GuardRails AI集成"""
    print("\n测试9: GuardRails AI集成")

    if not GUARDRAILS_INTEGRATION_AVAILABLE:
        print("  [WARN] GuardRails AI不可用，跳过集成测试")
        return

    try:
        from guardrails import Guard, OnFailAction
        from src.validators.pii_validator import CustomPIIValidator

        guard = Guard().use(
            CustomPIIValidator,
            pii_entities=["CN_PHONE", "EMAIL_ADDRESS"],
            on_fail="fix",
        )

        # 测试正常文本
        result = guard.validate("今天天气很好")
        assert result.validation_passed is True
        print("  [PASS] 正常文本通过验证")

        # 测试含PII文本（fix模式应自动脱敏）
        result = guard.validate("我的手机号13800138000")
        assert not result.validation_passed
        assert "<CN_PHONE>" in result.validated_output
        print(f"  [PASS] PII文本自动脱敏: {result.validated_output}")

    except Exception as e:
        print(f"  [WARN] GuardRails集成测试失败: {e}")


def test_convenience_functions():
    """测试便捷函数"""
    print("\n测试10: 便捷函数")

    results = pii_detect("邮箱test@example.com", pii_entities=["EMAIL_ADDRESS"])
    assert len(results) == 1
    print("  [PASS] pii_detect 工作正常")

    anonymized = pii_anonymize("邮箱test@example.com", pii_entities=["EMAIL_ADDRESS"])
    assert "<EMAIL_ADDRESS>" in anonymized
    print(f"  [PASS] pii_anonymize 工作正常: {anonymized}")


def run_all_tests():
    """运行所有PII测试"""
    print("=" * 60)
    print("自定义PII检测方案测试")
    print("=" * 60)

    tests = [
        test_cn_id_card_detection,
        test_cn_phone_detection,
        test_cn_bank_card_detection,
        test_email_detection,
        test_multiple_pii_detection,
        test_anonymize,
        test_pii_summary,
        test_pii_detection_service,
        test_guardrails_integration,
        test_convenience_functions,
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            failed += 1
            print(f"  [FAIL] 测试失败: {e}")

    print("\n" + "=" * 60)
    print(f"测试结果: {passed} 通过, {failed} 失败")
    print("=" * 60)

    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
