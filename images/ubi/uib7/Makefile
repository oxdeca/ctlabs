ubi7:	base_img

base_img: ubi
	cd base && sh ./build.sh

ubi:
	docker login https://registry.redhat.io && docker pull registry.redhat.io/ubi7
