# \file iiVaultTransitions.r
# \brief Copy folders to the vault
#
# \copyright Copyright (c) 2017, Utrecht university. All rights reserved
# \license GPLv3, see LICENSE


# \brief iiVaultStatus Retrieve current vault folder status
# \param[in]  folder	    Path of vault folder
# \param[out] folderStatus  Current status of vault folder
iiVaultStatus(*folder, *vaultStatus) {
	*vaultStatusKey = IIVAULTSTATUSATTRNAME;
	*vaultStatus = UNPUBLISHED;
	foreach(*row in SELECT META_COLL_ATTR_VALUE WHERE COLL_NAME = *folder AND META_COLL_ATTR_NAME = *vaultStatusKey) {
		*vaultStatus = *row.META_COLL_ATTR_VALUE;
	}
}

# \brief iiVaultGetActionActor Retrieve actor of action on vault folder
# \param[in]  folder      Path of action vault folder
# \param[out] actionActor Actor of action on vault folder
iiVaultGetActionActor(*folder, *actor, *actionActor) {
	# Retrieve vault folder collection id.
	foreach(*row in SELECT COLL_ID WHERE COLL_NAME = *folder) {
	        *collId = *row.COLL_ID;
	}

	# Retrieve vault folder action actor.
	*actionActor = "";
        foreach(*row in SELECT COLL_ID, META_COLL_ATTR_VALUE WHERE META_COLL_ATTR_NAME = "org_vault_action_*collId") {
	        *err = errorcode(msi_json_arrayops(*row.META_COLL_ATTR_VALUE, *actionActor, "get", 2));
		if (*err < 0) {
		   writeLine("serverLog", "iiVaultGetActionActor: org_vault_action_*collId contains invalid JSON");
		}
	}

	# Fallback actor (rodsadmin).
        if (*actionActor == "") {
                *actionActor = *actor;
        }
}

# \brief iiPreVaultStatusTransition  Actions taken before vault status transition
# \param[in] folder            Path of vault folder
# \param[in] currentStatus     Current status of vault folder
# \param[in] newStatus         New status of vault folder
iiPreVaultStatusTransition(*folder, *currentVaultStatus, *newVaultStatus) {
	on (*currentVaultStatus == SUBMITTED_FOR_PUBLICATION && *newVaultStatus == UNPUBLISHED) {
		*actor = uuClientFullName;
	        iiVaultGetActionActor(*folder, *actor, *actionActor);
		iiAddActionLogRecord(*actionActor, *folder, "canceled publication");
	}
	on (true) {
		nop;
	}
}

# \brief iiVaultRequestStatusTransition   Request vault status transition action
# \param[in] folder
# \param[in] newFolderStatus
# \param[in] actor
iiVaultRequestStatusTransition(*folder, *newVaultStatus, *status, *statusInfo) {
	*status = "Unknown";
	*statusInfo = "An internal error has occurred";

	uuGetUserType(uuClientFullName, *userType);
	if (*newVaultStatus == PUBLISHED && *userType != "rodsadmin") {
		*status = "PermissionDenied";
		*statusInfo = "Vault status request for published can only be requested by a rodsadmin.";
		succeed;
        }

	# Determine vault group and actor.
	*pathElems = split(*folder, "/");
	*rodsZone = elem(*pathElems, 0);
        *vaultGroup = elem(*pathElems, 2);
	*actor = uuClientFullName;

	# Check if user is manager of research group.
	iiCollectionGroupNameAndUserType(*folder, *actorGroup, *userType, *isDatamanager);

	# Status SUBMITTED_FOR_PUBLICATION can only be requested by researcher.
	if (*newVaultStatus == SUBMITTED_FOR_PUBLICATION && !*isDatamanager) {
		*actorGroupPath = "/*rodsZone/home/*actorGroup";
	# Status UNPUBLISHED can be called by researcher and datamanager.
	} else 	if (*newVaultStatus == UNPUBLISHED && !*isDatamanager) {
		*actorGroupPath = "/*rodsZone/home/*actorGroup";
	} else 	if (*isDatamanager) {
		iiDatamanagerGroupFromVaultGroup(*vaultGroup, *actorGroup);
		*actorGroupPath = "/*rodsZone/home/*actorGroup";
	}

	# Retrieve collection id.
	foreach(*row in SELECT COLL_ID WHERE COLL_NAME = *folder) {
		*collId = *row.COLL_ID;
	}

	# Check if vault package is currently pending for status transition.
	# Except for status transition to PUBLISHED, becuase it is requested
	# by the system before previous pending transition is removed.
	if (*newVaultStatus != PUBLISHED) {
		*pending = false;
		*vaultActionStatus = UUORGMETADATAPREFIX ++ "vault_status_action_*collId";
		foreach(*row in SELECT COLL_ID WHERE META_COLL_ATTR_NAME = *vaultActionStatus AND META_COLL_ATTR_VALUE = 'PENDING') {
			*pending = true;
		}

		# Don't accept request if a status transition is already pending.
		if (*pending) {
			*status = "PermissionDenied";
			*statusInfo = "Vault package is being processed, please wait until finished.";
			succeed;
		}
	}

	# Check if status transition is allowed.
	iiVaultStatus(*folder, *currentVaultStatus);
	iiCanTransitionVaultStatus(*folder, *currentVaultStatus, *newVaultStatus, *actor, *allowed, *reason);
	if (!*allowed) {
		*status = "PermissionDenied";
		*statusInfo = *reason;
		succeed;
	}

	# Add vault action request to actor group.
	writeLine("serverLog", "iiVaultRequestStatusTransition: *newVaultStatus on *folder by *actor");
        *json_str = "[]";
        *size = 0;
        msi_json_arrayops(*json_str, *folder, "add", *size);
        msi_json_arrayops(*json_str, *newVaultStatus, "add", *size);
        msi_json_arrayops(*json_str, *actor, "add", *size);
        msiString2KeyValPair("", *kvp);
        msiAddKeyVal(*kvp, UUORGMETADATAPREFIX ++ "vault_action_" ++ *collId, *json_str);
	*err = errormsg(msiAssociateKeyValuePairsToObj(*kvp, *actorGroupPath, "-C"), *msg);
	if (*err < 0) {
		*status = "Unrecoverable";
		*statusInfo = "*err - *msg";
		succeed;
        }

	# Add vault action status to actor group.
	# Used in frontend to check if vault package is in state transition.
	*vaultStatus = UUORGMETADATAPREFIX ++ "vault_status_action_" ++ "*collId=PENDING";
	msiString2KeyValPair(*vaultStatus, *kvp);
	*err = errormsg(msiAssociateKeyValuePairsToObj(*kvp, *actorGroupPath, "-C"), *msg);
	if (*err < 0) {
		*status = "Unrecoverable";
		*statusInfo = "*err - *msg";
		succeed;
	} else {
		*status = "Success";
		*statusInfo = "";
		succeed;
	}
}

# \brief iiVaultProcessStatusTransition   Processing vault status transition request
# \param[in] folder
# \param[in] newFolderStatus
# \param[in] actor
iiVaultProcessStatusTransition(*folder, *newFolderStatus, *actor, *status, *statusInfo) {
	*status = "Unknown";
	*statusInfo = "An internal error has occurred";

	uuGetUserType(uuClientFullName, *userType);
	if (*userType != "rodsadmin") {
		writeLine("stdout", "iiVaultStatusTransition: Should only be called by a rodsadmin");
		fail;
	}

	# Check if status isn't transitioned already.
        *currentVaultStatus = "";
        foreach(*row in SELECT META_COLL_ATTR_VALUE WHERE COLL_NAME = *folder AND META_COLL_ATTR_NAME = IIVAULTSTATUSATTRNAME) {
                *currentVaultStatus = *row.META_COLL_ATTR_VALUE;
        }
        if (*currentVaultStatus == *newFolderStatus) {
                 *status = "Success";
                 *statusInfo = "";
                succeed;
        }

	# Run publish process if newFolderStatus is PUBLISHED
	if (*newFolderStatus == PUBLISHED) {
		iiProcessPublication(*folder);
	}

	# Set new vault status.
	*vaultStatusStr = IIVAULTSTATUSATTRNAME ++ "=" ++ *newFolderStatus;
	msiString2KeyValPair(*vaultStatusStr, *vaultStatusKvp);
	*err = errormsg(msiSetKeyValuePairsToObj(*vaultStatusKvp, *folder, "-C"), *msg);
	if (*err < 0) {
		iiVaultStatus(*folder, *currentFolderStatus);
		iiCanTransitionVaultStatus(*folder, *currentVaultStatus, *newFolderStatus, *actor, *allowed, *reason);
		if (!*allowed) {
			*status = "PermissionDenied";
			*statusInfo = *reason;
		} else {
			if (*err == -818000) {
				*status = "PermissionDenied";
				*statusInfo = "User is not permitted to modify folder status";
			} else {
				*status = "Unrecoverable";
				*statusInfo = "*err - *msg";
			}
		}
        } else {
		*status = "Success";
		*statusInfo = "";
	}
}

# \brief iiPostVaultStatusTransition   Processing after vault status is changed
# \param[in] folder         Folder in vault for state transition
# \param[in] actor          Actor of the status transition
# \param[in] newVaultStatus New vault status
iiPostVaultStatusTransition(*folder, *actor, *newVaultStatus) {
	on (*newVaultStatus == SUBMITTED_FOR_PUBLICATION) {
	        iiVaultGetActionActor(*folder, *actor, *actionActor);
		iiAddActionLogRecord(*actionActor, *folder, "submitted for publication");
	}
	on (*newVaultStatus == APPROVED_FOR_PUBLICATION) {
	        iiVaultGetActionActor(*folder, *actor, *actionActor);
		iiAddActionLogRecord(*actionActor, *folder, "approved for publication");
	}
	on (*newVaultStatus == PUBLISHED) {
		iiAddActionLogRecord("system", *folder, "published");
	}
	on (*newVaultStatus == DEPUBLISHED) {
	        iiVaultGetActionActor(*folder, *actor, *actionActor);
		iiAddActionLogRecord(*actionActor, *folder, "depublished");
	}
	on (true) {
		nop;
	}
}

# \brief iiVaultSubmit    Submit a folder in the vault for publication
# \param[in]  folder      Path of folder in vault to submit for publication
# \param[out] status      Status of the action
# \param[out] statusInfo  Informative message when action was not successful
iiVaultSubmit(*folder, *status, *statusInfo) {
	iiVaultRequestStatusTransition(*folder, SUBMITTED_FOR_PUBLICATION, *status, *statusInfo);
}

# \brief iiVaultApprove   Approve a folder in the vault for publication
# \param[in]  folder      Path of folder in vault to approve for publication
# \param[out] status      Status of the action
# \param[out] statusInfo  Informative message when action was not successful
iiVaultApprove(*folder, *status, *statusInfo) {
	iiVaultRequestStatusTransition(*folder, APPROVED_FOR_PUBLICATION, *status, *statusInfo);
}

# \brief iiVaultCancel    Cancel a submission in the vault for publication
# \param[in]  folder      Path of folder in vault to cancel publication
# \param[out] status      Status of the action
# \param[out] statusInfo  Informative message when action was not successful
iiVaultCancel(*folder, *status, *statusInfo) {
	iiVaultRequestStatusTransition(*folder, UNPUBLISHED, *status, *statusInfo);
}

# \brief iiVaultDepublish Depublish a folder in the vault
# \param[in]  folder      Path of folder in vault to depublish
# \param[out] status      Status of the action
# \param[out] statusInfo  Informative message when action was not successful
iiVaultDepublish(*folder, *confirmationVersion, *status, *statusInfo) {
	iiVaultRequestStatusTransition(*folder, DEPUBLISHED, *status, *statusInfo);
}


# \brief iiGetPublicationTermsText  Get the terms and agreements as text to be accepted by researcher
# \param[in] folder            	Path of vault folder
# \param[out] result		Terms and agreements text 
# \param[out] status     	Status of the action
# \param[out] statusInfo        Information message when action was not successful
iiGetPublicationTermsText(*folder, *result, *status, *statusInfo)
{
	*status = "Unknown";
	*statusInfo = "";
	
	*termsColl = "/" ++ $rodsZoneClient ++ IITERMSCOLLECTION;

	*dataName = "";
	foreach (*row in SELECT DATA_NAME, DATA_SIZE, order_desc(DATA_MODIFY_TIME) WHERE COLL_NAME = *termsColl) {
		*dataModifyTime = *row.DATA_MODIFY_TIME;
		*dataName = *row.DATA_NAME;
		*dataSize = *row.DATA_SIZE;
		break;
	}

	if (*dataName == "") {
		*status = "NotFound";
		*statusInfo = "No Terms and Agreements found. Please contact YoDa administrators";
		succeed;
	}
 
	#DEBUG writeLine("serverLog", "iiGetPublicationTermsText: Opening *termsColl/*dataName last modified at *dataModifyTime");

	*err = errorcode(msiDataObjOpen("objPath=*termsColl/*dataName", *fd));
	if (*err < 0) {
		writeLine("serverLog", "iiGetPublicationTermsText: Opening *termsColl/*dataName failed with errorcode: *err");
		*status = "PermissionDenied";
		*statusInfo = "Could not open Terms and Agreements. Please contact YoDa administrators";
		succeed;
	}

	*err1 = errorcode(msiDataObjRead(*fd, *dataSize, *buf));
	*err2 = errorcode(msiDataObjClose(*fd, *status));
	*err3 = errorcode(msiBytesBufToStr(*buf, *result));
	if (*err1 == 0 && *err2 == 0 && *err3 == 0) {
		*status = "Success";
	} else {
		writeLine("serverLog", "iiGetPublicationTermsText: Reading *termsColl/*dataName failed with errorcode: *err1, *err2, *err3.");
		*status = "ReadFailure";
		*statusInfo = "Failed to read Terms and Agreements from disk. Please contact YoDa administrators";
	}
}	

