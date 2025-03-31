c9:	base_img frr_img ovs_img ctrl_img qemu_img

xv6_img:	base_img
	cd xv6 && sh ./build.sh

qemu_img:	base_img
	cd qemu && sh ./build.sh

ctrl_img:	base_img
	cd ctrl && sh ./build.sh

frr_img:	base_img
	cd frr && sh ./build.sh

ovs_img:	base_img
	cd ovs && sh ./build.sh

base_img:	centos
	cd base && sh ./build.sh

awscli_img:
	cd awscli && sh ./build.sh
	
gcsdk_img:
	cd gcsdk && sh ./build.sh
	
centos:
	docker pull quay.io/centos/centos:stream9
