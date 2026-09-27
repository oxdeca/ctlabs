qemu: base_img d12_img c9_img

win22_img: base_img
	cd win/2022 && sh ./build.sh

c9_img: base_img
	cd centos/c9 && sh ./build.sh
	
d12_img: base_img
	cd debian/d12 && sh ./build.sh

base_img: debian
	cd base && sh ./build.sh
root@c9-2:~/ctlabs/images/qemu# 
