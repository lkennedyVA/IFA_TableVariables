USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspOrgInsertOutBuild
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will insert a new record
	Tables: [organization].[Org]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2015-10-14 - LBD - Modified, check for existenced, code and orgtype must be unique
		2016-08-15 - LBD - Modified, @pnvCode must be nvarchar(25)
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgInsertOutBuild](
	 @piOrgTypeId INT
	,@pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@pnvExternalCode NVARCHAR(50)
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Org table (
		 OrgId int
		,OrgTypeId int
		,Code nvarchar(25)
		,Name nvarchar(50)
		,Descr nvarchar(255)
		,ExternalCode nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	IF @piOrgId IS NULL
	BEGIN
		--check if it already exists...
		SELECT @piOrgId = OrgId
		FROM [organization].[Org] o
		INNER JOIN [organization].[OrgType] ot on o.OrgTypeId = ot.OrgTypeId
		WHERE o.Code = @pnvCode
			AND ot.OrgTypeId = @piOrgTypeId;
		IF ISNULL(@piOrgId,-1) = -1
		BEGIN
			BEGIN TRANSACTION
			BEGIN TRY
				INSERT INTO [organization].[Org]
					OUTPUT inserted.OrgId
						,inserted.OrgTypeId
						,inserted.Code
						,inserted.Name
						,inserted.Descr
						,inserted.ExternalCode
						,inserted.StatusFlag
						,inserted.DateActivated
						,inserted.UserName
					INTO @Org
				SELECT @piOrgTypeId
					,@pnvCode
					,@pnvName
					,@pnvDescr
					,@pnvExternalCode
					,@piStatusFlag
					,SYSDATETIME()
					,@pnvUserName; 
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					ROLLBACK TRANSACTION;
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				SET @piOrgId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			END CATCH;
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			BEGIN
				COMMIT TRANSACTION;
				SELECT @piOrgId = OrgId
				FROM @Org
			END
		END --doesn't already exist
	END
	ELSE
	BEGIN
		SET IDENTITY_INSERT [organization].[Org] ON
		INSERT INTO [organization].[Org](OrgId, OrgTypeId, Code, Name, Descr, ExternalCode, StatusFlag, DateActivated, UserName)
		SELECT @piOrgId
			,@piOrgTypeId
			,@pnvCode
			,@pnvName
			,@pnvDescr
			,@pnvExternalCode
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
		SET IDENTITY_INSERT [organization].[Org] OFF
	END
END
