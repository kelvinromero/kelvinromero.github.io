DC = docker compose

run:
	${DC} up --build

stop:
	${DC} down
