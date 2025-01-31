USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgClientAcceptedXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-08-04
	Description: This procedure will insert a new xref record
	Tables: [organization].[OrgClientAcceptedXref]
	History:
		2015-08-04 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgClientAcceptedXrefInsertOut](
    @piOrgId INT
	,@piClientAcceptedId INT
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgClientAcceptedXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
   DECLARE @OrgClientAcceptedXref table (
		OrgClientAcceptedXrefId int
		,OrgId int
		,ClientAcceptedId int
		,StatusFlagD int
		,DateActivated datetime2(7)
      ,UserName nvarchar(100)
		);
   DECLARE @iErrorDetailId int
      ,@iCurrentTransactionLevel int
      ,@sSchemaName nvarchar(128) = N'organization';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [organization].[OrgClientAcceptedXref]
         OUTPUT inserted.OrgClientAcceptedXrefId
            ,inserted.OrgId
            ,inserted.ClientAcceptedId
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @OrgClientAcceptedXref
      SELECT @piOrgId
         ,@piClientAcceptedId
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > 0
         ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgClientAcceptedXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > 0
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piOrgClientAcceptedXrefId = OrgClientAcceptedXrefId
      FROM @OrgClientAcceptedXref
   END
END
