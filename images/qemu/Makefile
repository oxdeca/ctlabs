qemu: base_img d12_img c9_img

win22_core_img: base_img
	cd win/2022 && sh ./build.sh core

win22_dtop_img: base_img
	cd win/2022 && sh ./build.sh dtop

win25_core_img: base_img
	cd win/2025 && sh ./build.sh core

win25_dtop_img: base_img
	cd win/2025 && sh ./build.sh dtop

c9_img: base_img
	cd centos/c9 && sh ./build.sh
	
d12_img: base_img
	cd debian/d12 && sh ./build.sh

base_img: debian
	cd base && sh ./build.sh
