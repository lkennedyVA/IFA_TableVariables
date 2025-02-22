USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgFlowOptionXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new xref record
	Tables: [organization].[OrgFlowOptionXref]
	History:
		2015-05-07 - LBD - Created, this procedure takes codes as inputs, returns xrefId
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgFlowOptionXrefInsertOut](
    @piOrgId INT
	,@piFlowOptionId INT
	,@pnvFlowOptionValue NVARCHAR(50)
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgFlowOptionXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
   DECLARE @OrgFlowOptionXref table (
		OrgFlowOptionXrefId int
		,OrgId int
		,FlowOptionId int
		,FlowOptionValue nvarchar(25)
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
      INSERT INTO [organization].[OrgFlowOptionXref]
         OUTPUT inserted.OrgFlowOptionXrefId
            ,inserted.OrgId
            ,inserted.FlowOptionId
				,inserted.FlowOptionValue
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @OrgFlowOptionXref
      SELECT @piOrgId
         ,@piFlowOptionId
			,@pnvFlowOptionValue
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > 0
         ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgFlowOptionXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > 0
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piOrgFlowOptionXrefId = OrgFlowOptionXrefId
      FROM @OrgFlowOptionXref
   END
END
