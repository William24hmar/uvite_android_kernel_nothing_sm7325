# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the fingerprint drivers.
#
goodix_fp-y += gf_spi.o platform.o netlink.o

obj-$(CONFIG_GOODIX_FINGERPRINT) += goodix_fp.o

# Each configuration option enables a list of files.

obj-$(CONFIG_FINGERPRINT_FPC)		+= fpc/
obj-$(CONFIG_FINGERPRINT_GOODIX_FOD)	+= goodix/
