# Product Public Key

把签发方 `dl-issuer` 生成的产品公钥放在这里，命名为 `product_public_key.pem`，应用启动时会自动加载并设置到 DecentriLicense 客户端，用于离线验签。

示例：

```
cp /Volumes/workspace/project/ccait/dl-issuer/server/keys/product_public_key.pem ./product_public_key.pem
```

> 测试期可以留空，应用不会崩溃，但离线验签会失败。
