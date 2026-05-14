resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal key for ${local.name_prefix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-vault-unseal"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal-${var.environment}"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

data "aws_iam_policy_document" "vault_kms" {
  statement {
    sid    = "VaultKMSUnseal"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.vault_unseal.arn]
  }
}

resource "aws_iam_policy" "vault_kms" {
  name        = "${local.name_prefix}-vault-kms"
  description = "Allow Vault to use KMS for auto-unseal"
  policy      = data.aws_iam_policy_document.vault_kms.json
}
