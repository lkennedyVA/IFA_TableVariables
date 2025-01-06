USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLocationUpdate
	Created By: Chris Sharp
	Descr: This procedure will update the the Org information but doesnt allow updating 
		the StatusFlag of the Org. 
		If a ChannelId is passed in and that value differs from the ChannelId associated 
		with the OrgXref record in the channel dimension, we need to deactivate the 
		existing OrgXrefId prior to inserting a new OrgXref record for @piChannelId.
		We check for the existance of an address associated with the Org.  If we find
		a match, we update the existing address record.  If we dont find an existing 
		address, we need to insert a new Address record, checking for all pertinent 
		address information.  If we cant find an existing OrgAddressXref record, we 
		insert a new one.
	
	Tables: [common].[Address]
		,[organization].[Org]
		,[organization].[OrgAddressXref]
		,[organization].[OrgType]
		,[organization].[OrgXref]

	Functions: [common].[ufnDimension]
		,[common].[ufnOrgChannelId]
		,[command].[ufnOrgTypeLevelId]
		,[command].[ufnOrgType]
   
	Procedures: [error].[uspLogErrorDetailInsertOut]
		,[organization].[uspOrgUpdateOut]
		,[organization].[uspOrgXrefStatusFlagClearOut]
		,[organization].[uspOrgXrefInsertOut]
		,[common].[uspAddressUpdateOut]
		,[common].[uspAddressInsertOut]
		,[organization].[uspOrgAddressXrefInsertOut]	
		,[command].[uspLocationSelect]

	History:
		2018-02-08 - CBS - Created
		2018-02-14 - CBS - Modified, one additional restriction @biAddressId must be > 0
			to enter into uspOrgAddressXrefInsertOut
		2018-02-23 - CBS - Modified, added ExternalCode to OrgName exception since OrgNames
			are no longer unique.
*****************************************************************************************/
ALTER PROCEDURE [command].[uspLocationUpdate](
	 @piOrgId INT
	,@pnvOrgCode NVARCHAR(25) = N''
	,@pnvOrgName NVARCHAR(50) = N''
	,@pnvOrgDescr NVARCHAR(255) = N''
	,@pnvExternalCode NVARCHAR(50) = N''
	,@piOrgTypeId INT 
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100)
	,@piChannelId INT = -1
	,@pnvAddress1 NVARCHAR(150) = N''
	,@pnvAddress2 NVARCHAR(150) = N'' 
	,@pnvCity NVARCHAR(150) = N''	
	,@pnvStateAbbv NVARCHAR(2) = N''
	,@pnvZipCode NCHAR(9) = N''		
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblOrg table (
		 OrgId int
		,OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,ExternalCode nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		,ParentOrgId int
		,ParentOrgTypeId int
		,ChannelName nvarchar(50)
	);
	DECLARE @iChannelId int = [common].[ufnOrgChannelId](@piOrgId)
		,@iChannelDimensionId int = [common].[ufnDimension]('Channel')
		,@iChannelParentOrgId int = [common].[ufnOrgChannelOrgId](@piOrgId)
		,@biAddressId bigint 
		,@iOrgXrefId int 
		,@iOrgAddressXrefId int
		,@nvCountry nvarchar(100) = N'USA'
		,@fLatitude float = -1
		,@fLongitude float = -1
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'command';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	IF EXISTS(SELECT 'X' 
			FROM [organization].[Org]
			WHERE OrgId <> @piOrgId
				AND Code = @pnvOrgCode)
	BEGIN
		RAISERROR ('An Org with this OrgCode already exists',16,1);
		RETURN
	END
	ELSE IF EXISTS(SELECT 'X' 
				FROM [organization].[Org]
				WHERE OrgId <> @piOrgId
					AND [Name] = @pnvOrgName
					AND ExternalCode = @pnvExternalCode) --2018-02-23
	BEGIN
	RAISERROR ('An Org with this OrgName already exists',16,1);
		RETURN
	END
	ELSE IF EXISTS(SELECT 'X' 
				FROM [organization].[Org]
				WHERE OrgId <> @piOrgId
					AND ExternalCode = @pnvExternalCode)
	BEGIN
		RAISERROR ('An Org with this ExternalCode already exists',16,1);
		RETURN
	END
	IF EXISTS(SELECT 'X'
			FROM [organization].[Org]
			WHERE OrgId = @piOrgId
				AND OrgTypeId = @piOrgTypeId)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			--Using the procedure will allow update to the Org record but doesnt 
			--allow "Clear"ing the StatusFlag
			EXECUTE [organization].[uspOrgUpdateOut]
				 @pnvCode = @pnvOrgCode
				,@pnvName = @pnvOrgName
				,@pnvDescr = @pnvOrgDescr
				,@pnvUserName = @pnvUserName 
				,@piOrgId = @piOrgId OUTPUT;

			--If a ChannelId is passed in and that value differs from the
			--ChannelId associated with the OrgXref record in the channel 
			--dimension, we need to deactivate the existing OrgXrefId prior
			--to inserting a new OrgXref record for @piChannelId
			IF ISNULL(@piChannelId, -1) <> -1
				AND @piChannelId <> @iChannelId
			BEGIN 
				SELECT @iOrgXrefId = OrgXrefId
				FROM [organization].[OrgXref]
				WHERE DimensionId = @iChannelDimensionId
					AND OrgParentId = @iChannelParentOrgId
					AND OrgChildId = @piOrgId
					AND StatusFlag = 1; 
				--Deactivate the existing OrgXrefId
				IF ISNULL(@iOrgXrefId, -1) <> -1
					EXECUTE [organization].[uspOrgXrefStatusFlagClearOut]
						 @piDimensionId = @iChannelDimensionId
						,@pnvUserName = @pnvUserName
						,@piOrgXrefId = @iOrgXrefId OUTPUT;
				
					SELECT @iChannelParentOrgId = o.OrgId 
					FROM [organization].[Org] o
					INNER JOIN [organization].[OrgType] ot 
						ON o.OrgTypeId = ot.OrgTypeId
					WHERE ot.[Name] = 'Channel'
						AND CASE o.[Name] WHEN 'Teller' THEN 1
											WHEN 'ATM' THEN 2
											WHEN 'Mobile' THEN 3
											ELSE 0
										END = @piChannelId;

					--Inserting a new OrgXref record in the Channel Dimesion
					SET @iOrgXrefId = NULL;
					EXECUTE [organization].[uspOrgXrefInsertOut]
						 @piDimensionid = @iChannelDimensionId
						,@piOrgParentId = @iChannelParentOrgId
						,@piOrgChildId = @piOrgId
						,@piStatusFlag = 1
						,@pnvUserName = @pnvUserName 
						,@piOrgXrefId = @iOrgXrefId OUTPUT;
			END
					
			--Retrive the AddressId and OrgAddressXrefId 
			--to give us enough information to make determinations
			SELECT @biAddressId = oax.AddressId
				,@iOrgAddressXrefId = oax.OrgAddressXrefId
			FROM [common].[Address] a
			INNER JOIN [organization].[OrgAddressXref] oax
				ON a.AddressId = oax.AddressId
			WHERE oax.OrgId = @piOrgId;

			SET @biAddressId = ISNULL(@biAddressId, -1);
			SET @iOrgAddressXrefId = ISNULL(@iOrgAddressXrefId, -1);

			--If @biAddressId > 0 we need to update an existing Address record
			IF @biAddressId > 0
				EXECUTE [common].[uspAddressUpdateOut]
					 @pnvAddress1 = @pnvAddress1
					,@pnvAddress2 = @pnvAddress2
					,@pnvCity = @pnvCity
					,@pnvStateAbbv = @pnvStateAbbv
					,@pnvZipCode = @pnvZipCode
					,@pnvCountry = @nvCountry
					,@pfLatitude = @fLatitude
					,@pfLongitude = @fLongitude
					,@piStatusFlag = @piStatusFlag
					,@pnvUserName = @pnvUserName
					,@pbiAddressId = @biAddressId OUTPUT;
			--If @biAddressId < 0 we need to insert a new Address record
			--Must have all pertinent address information
			ELSE IF @biAddressId < 0
				AND ISNULL(@pnvAddress1, '') <> ''
				AND ISNULL(@pnvCity, '') <> ''
				AND ISNULL(@pnvStateAbbv, '') <> ''
				AND ISNULL(@pnvZipCode, '') <> ''
				EXECUTE [common].[uspAddressInsertOut]
					 @pnvAddress1 = @pnvAddress1
					,@pnvAddress2 = @pnvAddress2
					,@pnvCity = @pnvCity
					,@pnvStateAbbv = @pnvStateAbbv
					,@pnvZipCode = @pnvZipCode
					,@pnvCountry = @nvCountry
					,@pfLatitude = @fLatitude
					,@pfLongitude = @fLongitude
					,@piStatusFlag = @piStatusFlag
					,@pnvUserName = @pnvUserName
					,@pbiAddressId = @biAddressId OUTPUT;
			--If @iOrgAddressXrefId < 0 we need to insert a new OrgAddressXref record
			IF @iOrgAddressXrefId < 0
				AND @biAddressId > 0 --2018-02-14
				EXECUTE [organization].[uspOrgAddressXrefInsertOut]		
					 @piOrgId = @piOrgId
					,@pbiAddressId = @biAddressId
					,@pfLatitude = @fLatitude
					,@pfLongitude = @fLongitude
					,@piStatusFlag = @piStatusFlag
					,@pnvUserName = @pnvUserName
 					,@piOrgAddressXrefId = @iOrgAddressXrefId OUTPUT;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;	
			EXECUTE [command].[uspLocationSelect] @piOrgId = @piOrgId; 
		END
	END
END
