# \brief iiSearchByName		Search for a file or collection by name
# \param[in] startpath		Path to start searching. Defaults to /{rodsZoneClient}/home/
# \param[in] searchString	String to search for in the filesystem
# \param[in] collectionOrDataObject	Either "Collection" or "DataObject"
# \param[in] orderby		Column to sort on, Defaults to COLL_NAME
# \param[in] ascdesc		"asc" for ascending order and "desc" for descending order
# \param[in] limit		Maximum number of results returned
# \param[in] offset		Offset in result set before returning results
# \param[out] result		List of results in JSON format
# \param[out] status            Status code: 'Success' of all ok
# \param[out] statusInfo        Extra information if something went wrong
iiSearchByName(*startpath, *searchString, *collectionOrDataObject, *orderby, *ascdesc, *limit, *offset, *result, *status, *statusInfo) {
	*status='Success';
	*statusInfo = '';
	*iscollection = iscollection(*collectionOrDataObject);
	if (*iscollection) {
		*fields = list("COLL_PARENT_NAME", "COLL_ID", "COLL_NAME", "COLL_MODIFY_TIME", "COLL_CREATE_TIME");
		*conditions = list(uumakelikecollcondition("COLL_NAME", *searchString));
		*conditions = cons(uumakestartswithcondition("COLL_PARENT_NAME", *startpath), *conditions);
		uuPaginatedUpperQuery(*fields, *conditions, *orderby, *ascdesc, *limit, *offset, *rowList, *status, *statusInfo);
		if (*status!='Success') {
			succeed;
		}

		iiKvpCollectionTemplate(*rowList, *kvpList);
	} else {
		*fields = list("COLL_NAME", "DATA_ID", "DATA_NAME", "MIN(DATA_CREATE_TIME)", "MAX(DATA_MODIFY_TIME)");
		*conditions = list(uumakelikecondition("DATA_NAME", *searchString));
		*conditions = cons(uumakestartswithcondition("COLL_NAME", *startpath), *conditions);
		uuPaginatedUpperQuery(*fields, *conditions, *orderby, *ascdesc, *limit, *offset, *rowList, *status, *statusInfo);
                if (*status!='Success') {
                        succeed;
                }

		iiKvpDataObjectsTemplate(*rowList, *kvpList);
	}

	uuKvpList2JSON(*kvpList, *json_str, *size);
	*result = *json_str;
}

# \brief iiSearchByMetadata	Search for a file or collection by metadata
# \param[in] startpath		Path to start searching. Defaults to /{rodsZoneClient}/home/
# \param[in] searchString	String to search for in the filesystem
# \param[in] searchStringEscaped	Escaped string to search for in the filesystem
# \param[in] collectionOrDataObject	Either "Collection" or "DataObject"
# \param[in] orderby		Column to sort on, Defaults to COLL_NAME
# \param[in] ascdesc		"asc" for ascending order and "desc" for descending order
# \param[in] limit		Maximum number of results returned
# \param[in] offset		Offset in result set before returning results
# \param[out] result		List of results in JSON format
# \param[out] status            Status code: 'Success' of all ok
# \param[out] statusInfo        Extra information if something went wrong
iiSearchByMetadata(*startpath, *searchString, *searchStringEscaped, *collectionOrDataObject, *orderby, *ascdesc, *limit, *offset, *result, *status, *statusInfo) {
	*status='Success';
        *statusInfo = '';

	*iscollection = iscollection(*collectionOrDataObject);
	*likeprefix = UUUSERMETADATAPREFIX ++ "%";
	if (*iscollection) {
		*fields = list("COLL_PARENT_NAME", "COLL_ID", "COLL_NAME", "COLL_MODIFY_TIME", "COLL_CREATE_TIME");
		*conditions = list(uumakelikecondition("META_COLL_ATTR_VALUE", *searchStringEscaped),
				   uumakestartswithcondition("META_COLL_ATTR_NAME", UUUSERMETADATAPREFIX),
				   uumakestartswithcondition("COLL_PARENT_NAME", *startpath));
		uuPaginatedUpperQuery(*fields, *conditions, *orderby, *ascdesc, *limit, *offset, *rowList, *status, *statusInfo);
                if (*status!='Success') {
                        succeed;
                }

		iiKvpCollectionTemplate(*rowList, *kvpList);	
		foreach(*kvp in tl(*kvpList)) {
			*coll_id = *kvp.id;
			*msize = 0;
			*matches_lst = list();

			foreach(*row in SELECT META_COLL_ATTR_NAME, META_COLL_ATTR_VALUE WHERE COLL_ID = *coll_id AND META_COLL_ATTR_NAME like *likeprefix) {
				# Convert value and searchstring to uppercase for case insensitive search.
				msiStrToUpper(*row.META_COLL_ATTR_VALUE, *upperValue);
				msiStrToUpper(*searchString, *upperSearchstring);
				if (*upperValue like "**upperSearchstring*") {
					msiString2KeyValPair("", *match);
					*name_lst = split(*row.META_COLL_ATTR_NAME, "_");
					uuJoin(" ", tl(tl(*name_lst)), *name);
					*val = *row.META_COLL_ATTR_VALUE;
					msiAddKeyVal(*match, *name, *val);
					*match_json = "";
					msi_json_objops(*match_json, *match, "set");
					*matches_lst = cons(*match_json, *matches_lst);
				}
			}
			# Cannot rely on msi_json_arrayops as it removes double entries
			uuJoin(",", *matches_lst, *matches);
			*matches = "[" ++ *matches ++ "]";	
			*kvp.matches = *matches;
		}	
	} else {
		*fields = list("COLL_NAME", "DATA_ID", "DATA_NAME", "MIN(DATA_CREATE_TIME)", "MAX(DATA_MODIFY_TIME)");
		*conditions = list(uumakelikecondition("META_DATA_ATTR_VALUE", *searchStringEscaped),
				   uumakestartswithcondition("META_COLL_ATTR_NAME", UUUSERMETADATAPREFIX),
				   uumakestartswithcondition("COLL_NAME", *startpath));
		uuPaginatedUpperQuery(*fields, *conditions, *orderby, *ascdesc, *limit, *offset, *rowList, *status, *statusInfo);
                if (*status!='Success') {
                        succeed;
                }

		iiKvpDataObjectsTemplate(*rowList, *kvpList);
		# skip index 0, it contains the summary and then add user metadata matches to each kvp
		foreach(*kvp in tl(*kvpList)) {
			*data_id = *kvp.id;
			*matches_lst = list();
			*msize = 0;
			foreach(*row in SELECT META_DATA_ATTR_NAME, META_DATA_ATTR_VALUE WHERE DATA_ID = *data_id AND META_DATA_ATTR_NAME like *likeprefix) {
				# Convert value and searchstring to uppercase for case insensitive search.
				msiStrToUpper(*row.META_DATA_ATTR_VALUE, *upperValue);
				msiStrToUpper(*searchString, *upperSearchstring);
				if (*upperValue like "**upperSearchstring*") {
					msiString2KeyValPair("", *match);
					*name = triml(*row.META_DATA_ATTR_NAME, UUUSERMETADATAPREFIX);
					*val = *row.META_DATA_ATTR_VALUE;
					msiAddKeyVal(*match, *name, *val);
					*match_json = "";
					msi_json_objops(*match_json, *match, "set");
					*matches_lst = cons(*match_json, *matches_lst);
				}
			}
			# Cannot rely on msi_json_arrayops as it removes double entries
			uuJoin(",", *matches_lst, *matches);
			*matches = "[" ++ *matches ++ "]";	
			*kvp.matches = *matches;
		}	

	}

	uuKvpList2JSON(*kvpList, *json_str, *size);
	*result = *json_str;
}

# \brief iiSearchByOrgMetadata	Search for a collection by organisational metadata
# \param[in] startpath		Path to start searching. Defaults to /{rodsZoneClient}/home/
# \param[in] searchstring	String to search for in the organisational metadata
# \param[in] attrname		Name of the metadata attribute to query (without UUORGMETADATAPREFIX)
# \param[in] orderby		Column to sort on, Defaults to COLL_NAME
# \param[in] ascdesc		"asc" for ascending order and "desc" for descending order
# \param[in] limit		Maximum number of results returned
# \param[in] offset		Offset in result set before returning results
# \param[out] result		List of results in JSON format
# \param[out] status            Status code: 'Success' of all ok
# \param[out] statusInfo        Extra information if something went wrong

iiSearchByOrgMetadata(*startpath, *searchstring, *attrname, *orderby, *ascdesc, *limit, *offset, *result, *status, *statusInfo) {
	*status = 'Success';
	*statusInfo = '';

	*attr = UUORGMETADATAPREFIX ++ *attrname;
	*fields = list("COLL_PARENT_NAME", "COLL_ID", "COLL_NAME", "COLL_MODIFY_TIME", "COLL_CREATE_TIME");
	*conditions = list(uumakestartswithcondition("META_COLL_ATTR_VALUE", *searchstring));
	*conditions = cons(uucondition("META_COLL_ATTR_NAME", "=", *attr), *conditions);
	*conditions = cons(uumakestartswithcondition("COLL_NAME", *startpath), *conditions);
	uuPaginatedUpperQuery(*fields, *conditions, *orderby, *ascdesc, *limit, *offset, *rowList, *status, *statusInfo);
        if (*status!='Success') {
                succeed;
        }

	iiKvpCollectionTemplate(*rowList, *kvpList);
	uuKvpList2JSON(*kvpList, *result, *size);
}


# \brief iiKvpCollectionTemplate	convert a list of irods general query rows into a kvp list for collections
# \param[in] rowList	list of general query rows of collections
# \param[out] kvpList	list of key-value-pairs representing collections
iiKvpCollectionTemplate(*rowList, *kvpList) {
	*kvpList = list();
	foreach(*row in tl(*rowList)) {
		# Initialize new key-value-pair. Otherwise the same *kvp will be continuously overwritten
		msiString2KeyValPair("", *kvp);
		# Depending on irods type set key-values for *kvp
		*name =	*row.COLL_NAME;
		*kvp."path" = *name;
		*parent = *row.COLL_PARENT_NAME;
		*kvp.parent = *parent;
		*basename = triml(*name, *parent ++ "/");
		*kvp.basename = *basename;
		*coll_id = *row.COLL_ID;
		*kvp.id = *coll_id;
		*kvp."irods_type" = "Collection";
		*kvp."create_time" = *row.COLL_CREATE_TIME;
		*kvp."modify_time" = *row.COLL_MODIFY_TIME;
		# Add collection metadata with org prefix 	
		uuCollectionMetadataKvp(*coll_id, UUORGMETADATAPREFIX, *kvp);
		#! writeLine("stdout", *kvp);
		*kvpList = cons(*kvp, *kvpList);
	}
	*kvpList = cons(hd(*rowList), *kvpList);
}

# \brief iiKvpDataObjectsTemplate	convert a list of irods general query rows into a kvp list for collections
# \param[in] rowList	list of General Query rows for DataObjects
# \param[out] kvpList   list of key-value-pairs representing DataObjects
iiKvpDataObjectsTemplate(*rowList, *kvpList) {
	*kvpList = list();
	foreach(*row in tl(*rowList)) {
	# Initialize new key-value-pair. Otherwise the same *kvp will be continuously overwritten
		msiString2KeyValPair("", *kvp);
		*name = *row.DATA_NAME;
		*kvp.basename = *name;
		*parent = *row.COLL_NAME;
		*kvp.parent = *parent;
		*kvp."path" = *parent ++ "/" ++ *name;
		*data_id = *row.DATA_ID;
		*kvp.id = *data_id;
		*kvp."create_time" = *row.DATA_CREATE_TIME;
		*kvp."modify_time" = *row.DATA_MODIFY_TIME;
		*kvp."irods_type" = "DataObject";
		# Add Dataobject metadata with org prefix
		uuObjectMetadataKvp(*data_id, UUORGMETADATAPREFIX, *kvp);
		*kvpList = cons(*kvp, *kvpList);
	}
	*kvpList = cons(hd(*rowList), *kvpList);
}
