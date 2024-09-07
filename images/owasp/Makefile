owasp:  zap_img juice_img

juice_img:
	cd juice && sh ./build.sh

zap_img: zaproxy
	cd zap && sh ./build.sh

zaproxy:
	docker pull ghcr.io/zaproxy/zaproxy
