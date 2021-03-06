copyToVault {
	# This script is kept as dumb as possible. All processing and error handling is done by iiFolderSecure
	*ContInxOld = 1;
	msiAddSelectFieldToGenQuery("COLL_NAME", "", *GenQInp);	
	msiAddConditionToGenQuery("META_COLL_ATTR_NAME", "=", IISTATUSATTRNAME, *GenQInp);
	msiAddConditionToGenQuery("META_COLL_ATTR_VALUE", "=", ACCEPTED, *GenQInp);

	msiExecGenQuery(*GenQInp, *GenQOut);

	msiGetContInxFromGenQueryOut(*GenQOut, *ContInxNew);

	while(*ContInxOld > 0) {
		foreach(*row in *GenQOut) {
			*folder = *row.COLL_NAME;
			# When iiFolderSecure fails continue with the other folders.
			iiFolderSecure(*folder) ::: nop;
		}

		*ContInxOld = *ContInxNew;
		if(*ContInxOld > 0) {
			msiGetMoreRows(*GenQInp, *GenQOut, *ContInxNew);
		}
	}
}
input null
output ruleExecOut
