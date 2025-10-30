parrot:  base_img

ctf_img:  base_img
	cd ctf && sh ./build.sh

base_img: parrotsec
	cd base && sh ./build.sh

parrotsec:
	docker pull docker.io/parrotsec/security
