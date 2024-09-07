kali:  base_img

ctf_img:  base_img
	cd ctf && sh ./build.sh

base_img: kali_rolling
	cd base && sh ./build.sh

kali_rolling:
	docker pull docker.io/kalilinux/kali-rolling
