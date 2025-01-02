USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspClientInsert
	CreatedBy: Larry Dugger
	Descr: This procedure will insert a new record
	Tables: [organization].[Org]
		,[organization].[OrgXref]
	Funcs/Procs: [common].[ufnDimension]
		,[error].[uspLogErrorDetailInsertOut]
		,[organization].[ufnOrgType]
		,[command].[ufnOrgTypeLevelId]
	History:
		2017-11-21 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspClientInsert](
	 @pnvOrgName NVARCHAR(50)
	,@piParentOrgId INT
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Org table (
		 OrgId int
		,OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,ExternalCode nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @OrgXref table (
		 OrgXrefId int
		,DimensionId int
		,OrgParentId int
		,OrgChildId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);

	DECLARE @iClientOrgId int
		,@iClientOrgTypeId int = [command].[ufnOrgType]('Client')
		,@iClientLevelId int = [command].[ufnOrgTypeLevelId]('Client')
		,@iParentOrgLevelId int 
		,@iOrgXrefId int
		,@iDimensionid int = [common].[ufnDimension]('Organization')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'command';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	SELECT @iParentOrgLevelId = TRY_CONVERT(INT,ot.Code)
	FROM [organization].[Org] o
	INNER JOIN [organization].[OrgType] ot on o.OrgTypeId = ot.OrgTypeId
	WHERE o.OrgId = @piParentOrgId;

	IF @iClientLevelId > @iParentOrgLevelId
	BEGIN
		--check if it already exists...
		SELECT @iClientOrgId = OrgId
		FROM [organization].[Org] o
		WHERE o.[Name] = @pnvOrgName;
		IF ISNULL(@iClientOrgId,-1) = -1
		BEGIN
			BEGIN TRANSACTION
			BEGIN TRY
				INSERT INTO [organization].[Org]
					OUTPUT inserted.OrgId
						,inserted.OrgTypeId
						,inserted.Code
						,inserted.[Name]
						,inserted.Descr
						,inserted.ExternalCode
						,inserted.StatusFlag
						,inserted.DateActivated
						,inserted.UserName
					INTO @Org
				SELECT @iClientOrgTypeId
					,N''
					,@pnvUserName
					,N''
					,N''
					,@piStatusFlag
					,SYSDATETIME()
					,@pnvUserName; 
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					ROLLBACK TRANSACTION;
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				THROW
			END CATCH;
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			BEGIN
				COMMIT TRANSACTION;
				BEGIN TRANSACTION
				BEGIN TRY
					INSERT INTO [organization].[OrgXref](DimensionId,OrgParentId,OrgChildId,StatusFlag,DateActivated,UserName)
					SELECT @iDimensionid 
						,@piParentOrgId
						,OrgId
						,@piStatusFlag
						,SYSDATETIME()
						,@pnvUserName
					FROM @Org;
				END TRY
				BEGIN CATCH
					IF @@TRANCOUNT > @iCurrentTransactionLevel
						ROLLBACK TRANSACTION;
					EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
					THROW;
				END CATCH;
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					COMMIT TRANSACTION;
				SELECT OrgId, [Name] AS OrgName, @piParentOrgId AS ParentOrgId, StatusFlag, DateActivated, UserName
				FROM @Org
			END
		END
		ELSE
			RAISERROR ('Client already exists', 16, 1);
	END
	ELSE
		RAISERROR ('Client can only have a Parent with a lower OrgTypeCode', 16, 1);
END
