d11:    base_img smbadc_img qemu_img

qemu_img: base_img
	cd qemu && sh ./build.sh

smbadc_img:  base_img
	cd smbadc && sh ./build.sh

base_img: debian
	cd base && sh ./build.sh
debian:
	docker image pull docker.io/library/debian:11
