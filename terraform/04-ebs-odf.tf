# ==========================================
# 04. EBS Raw Disks untuk ODF / Local Storage Operator
# ==========================================
# 9 x gp3 300GB → raw block devices untuk LocalVolumeSet
# (hub/storage/local-volume/lvs.yaml, storageClassName: lvs-sc, volumeMode: Block)
#
# IKUTI toggle enable_hub: semua disk milik cluster HUB.
#
# Disk ini TIDAK di-attach otomatis: lifecycle node ODF dimiliki OpenShift
# Machine API (compute/machineSets/odf.yaml), bukan terraform. Attach manual
# dilakukan via console/CLI setelah apply — lihat README section 4.3.
# Zona mengikuti machineset odf (ap-southeast-1a) — EBS volume wajib
# satu-zona dengan instance tujuan.
locals {
  odf_local_disk_azs = ["ap-southeast-1a"]

  # urutan device name utk attach manual: 3 disk per node
  odf_local_disk_device_names = ["/dev/sdf", "/dev/sdg", "/dev/sdh"]
}

resource "aws_ebs_volume" "odf_local_volume_disk" {
  count = var.enable_hub ? var.odf_local_disk_count : 0

  availability_zone = local.odf_local_disk_azs[count.index % length(local.odf_local_disk_azs)]
  size              = var.odf_local_disk_size
  type              = var.odf_local_disk_type

  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-odf-local-disk-${format("%02d", count.index + 1)}"
    Cluster = "hub"
    Purpose = "odf-local-volume"
  })
}

output "odf_local_volume_ids" {
  description = "EBS volume IDs (gp3 300GB) untuk manual attach ke node ODF."
  value = {
    for i, v in aws_ebs_volume.odf_local_volume_disk :
    "${local.resource_prefix}-odf-local-disk-${format("%02d", i + 1)}" => v.id
  }
}
