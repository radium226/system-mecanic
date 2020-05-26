SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -e -c
.ONESHELL:

HARD_DRIVE_SIZE = 1G
HARD_DRIVE_LABEL = HARD_DRIVE

hard-drive.img:
	truncate --size="$(HARD_DRIVE_SIZE)" "./hard-drive.img"
	mkfs.btrfs "./hard-drive.img" -L "$(HARD_DRIVE_LABEL)"

/dev/disk/by-label/$(HARD_DRIVE_LABEL): hard-drive.img
	sudo losetup "$$( sudo losetup -f )" "./hard-drive.img"
	sleep 1

.PHONY: mount-hdd
mount-hdd: /dev/disk/by-label/$(HARD_DRIVE_LABEL)
	if ! mountpoint --quiet "./hard-drive"; then
		mkdir -p "./hard-drive"
		sudo mount "/dev/disk/by-label/$(HARD_DRIVE_LABEL)" "./hard-drive"
	fi

.PHONY: create-subvolumes
create-subvolumes: mount-hdd
	if [[ $$( sudo btrfs subvolume list | wc -l ) -eq 0 ]]; then  
		sudo btrfs subvolume create ./hard-drive/@
		sudo btrfs subvolume create ./hard-drive/@home
		sudo btrfs subvolume create ./hard-drive/@snapshots
	fi

.PHONY: mount-subvolumes
mount-subvolumes: create-subvolumes
	if ! mountpoint --quiet "./subvolumes"; then
		sudo mkdir -p "./subvolumes"
		sudo mount -o subvol="@" "/dev/disk/by-label/$(HARD_DRIVE_LABEL)" "./subvolumes"
	fi

	if ! mountpoint --quiet "./subvolumes/.snapshots"; then
		sudo mkdir -p "./subvolumes/.snapshots"
		sudo mount -o subvol="@snapshots" "/dev/disk/by-label/$(HARD_DRIVE_LABEL)" "./subvolumes/.snapshots"
	fi

	if ! mountpoint --quiet "./subvolumes/home"; then
		sudo mkdir -p "./subvolumes/home"
		sudo mount -o subvol="@home" "/dev/disk/by-label/$(HARD_DRIVE_LABEL)" "./subvolumes/home"
	fi

.PHONY: take-snapshot
take-snapshot:
	! test -d "./hard-drive/@snapshots/home" && sudo mkdir -p "./hard-drive/@snapshots/home" || true
	sudo btrfs subvolume snapshot "./subvolumes/home" "./hard-drive/@snapshots/home/$$( date -u +"%H:%M" )" -r

.PHONY: list-snapshots
list-snapshots:
	sudo btrfs subvolume list "./subvolumes"

.PHONY: rollback-snapshot
rollback-snapshot:
	sudo umount "./subvolumes/home"
	sudo mv "./hard-drive/@home" "./hard-drive/@home_CORRUPTED"
	sudo btrfs subvolume snapshot "./hard-drive/@snapshots/home/$(SNAPSHOT_TIME)" "./hard-drive/@home" 
	sudo mount -o subvol="@home" "/dev/disk/by-label/$(HARD_DRIVE_LABEL)" "./subvolumes/home"
	sudo btrfs subvolume delete ./hard-drive/@home_CORRUPTED

.PHONY: clean
clean:
	mountpoint --quiet "./subvolumes/.snapshots" && sudo umount "./subvolumes/.snapshots" || true
	mountpoint --quiet "./subvolumes/home"       && sudo umount "./subvolumes/home"       || true
	mountpoint --quiet "./subvolumes/"           && sudo umount "./subvolumes/"           || true
	
	if mountpoint --quiet "./hard-drive"; then
		dev_path="$$( mount | grep "$(PWD)/hard-drive" | cut -d' ' -f1 )"
		sudo umount "./hard-drive"
		sudo losetup -d "$${dev_path}"
		rmdir "./hard-drive"
	fi

	test -f "hard-drive.img" && rm "hard-drive.img" || true
	

.PHONY: test-e2e
test-e2e: hard-drive.img

