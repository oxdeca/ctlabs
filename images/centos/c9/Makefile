c9:	base_img frr_img ctrl_img qemu_img

xv6_img:	base_img
	cd xv6 && sh ./build.sh

qemu_img:	base_img
	cd qemu && sh ./build.sh

ctrl_img:	base_img
	cd ctrl && sh ./build.sh

frr_img:	base_img
	cd frr && sh ./build.sh

base_img:
	cd base && sh ./build.sh

awscli_img:
	cd awscli && sh ./build.sh
	
gcsdk_img:
	cd gcsdk && sh ./build.sh

