resource "aws_route53_zone" "public" {
  for_each = toset(var.public_hosted_zones)

  name = each.value
  tags = merge(local.common_tags, {
    Name = each.value
  })
}
